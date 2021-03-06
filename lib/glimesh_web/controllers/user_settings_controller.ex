defmodule GlimeshWeb.UserSettingsController do
  use GlimeshWeb, :controller

  alias Glimesh.Accounts
  alias Glimesh.Tfa
  alias GlimeshWeb.UserAuth

  plug :assign_email_and_password_changesets

  def edit(conn, _params) do
    render(conn, "edit.html")
  end

  def update_email(conn, %{"current_password" => password, "user" => user_params}) do
    user = conn.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_update_email_instructions(
          applied_user,
          user.email,
          &Routes.user_settings_url(conn, :confirm_email, &1)
        )

        conn
        |> put_flash(
          :info,
          dgettext(
            "profile",
            "A link to confirm your e-mail change has been sent to the new address."
          )
        )
        |> redirect(to: Routes.user_settings_path(conn, :edit))

      {:error, changeset} ->
        render(conn, "edit.html", email_changeset: changeset)
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_user, token) do
      :ok ->
        conn
        |> put_flash(:info, dgettext("profile", "E-mail changed successfully."))
        |> redirect(to: Routes.user_settings_path(conn, :edit))

      :error ->
        conn
        |> put_flash(
          :error,
          dgettext("errors", "Email change link is invalid or it has expired.")
        )
        |> redirect(to: Routes.user_settings_path(conn, :edit))
    end
  end

  def update_password(conn, %{"current_password" => password, "user" => user_params}) do
    user = conn.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, dgettext("profile", "Password updated successfully."))
        |> put_session(:user_return_to, Routes.user_settings_path(conn, :edit))
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, "edit.html", password_changeset: changeset)
    end
  end

  def update_profile(conn, %{"user" => user_params}) do
    user = conn.assigns.current_user

    case Accounts.update_user_profile(user, user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, dgettext("profile", "Profile updated successfully."))
        |> put_session(:user_return_to, Routes.user_settings_path(conn, :edit))
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, "edit.html", profile_changeset: changeset)
    end
  end

  def update_tfa(conn, %{"current_password" => password, "user" => %{"tfa" => pin}}) do
    user = conn.assigns.current_user

    IO.puts("is empty #{password == ""}")

    case Accounts.update_tfa(user, pin, password, %{
           tfa_token:
             if user.tfa_token do
               nil
             else
               get_session(conn, :tfa_secret)
             end
         }) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "2FA updated successfully.")
        |> put_session(:user_return_to, Routes.user_settings_path(conn, :edit))
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, "edit.html", tfa_changeset: changeset)
    end
  end

  def get_tfa(conn, _params) do
    user = conn.assigns.current_user

    secret =
      case get_session(conn, :tfa_secret) do
        nil -> Tfa.generate_secret(user.hashed_password)
        _ -> get_session(conn, :tfa_secret)
      end

    conn
    |> put_session(:tfa_secret, secret)
    |> text(Tfa.generate_tfa_img("Glimesh", user.username, secret))
  end

  defp assign_email_and_password_changesets(conn, _opts) do
    user = conn.assigns.current_user

    conn
    |> assign(:user, user)
    |> assign(:profile_changeset, Accounts.change_user_profile(user))
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:password_changeset, Accounts.change_user_password(user))
    |> assign(:tfa_changeset, Accounts.change_tfa(user))
  end
end
