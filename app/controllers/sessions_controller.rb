class SessionsController < ApplicationController
  skip_before_action :require_admin!

  def new
    redirect_to root_path if admin_signed_in?
  end

  def create
    auth = request.env["omniauth.auth"]
    email = auth&.dig("info", "email").to_s.downcase

    unless auth.present? && admin_email_allowed?(email)
      reset_session
      redirect_to sign_in_path, alert: "That Google account is not allowed."
      return
    end

    reset_session
    session[:admin_email] = email
    session[:admin_name] = auth.dig("info", "name").presence || email

    redirect_to root_path, notice: "Signed in."
  end

  def destroy
    reset_session
    redirect_to sign_in_path, notice: "Signed out."
  end

  def failure
    redirect_to sign_in_path, alert: "Google sign-in failed. Please try again."
  end
end
