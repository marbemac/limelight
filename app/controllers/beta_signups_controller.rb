class BetaSignupsController < ApplicationController
  def create
    signup = BetaSignup.new(params[:referer] ? params : params.merge(:referer => session['referer']))

    if signup.save

      if signup.source == 'Limelight'
        UserMailer.beta_signup_email(params[:email]).deliver
      end
      UserMailer.beta_signup_email_admins(params[:email], signup.id.to_s).deliver

      track_mixpanel("Request Beta Invite", signup.mixpanel_data)
      response = build_ajax_response(:ok, nil, nil)
      status = 201
    else
      response = build_ajax_response(:error, nil, "Sorry, there was an error", signup.errors)
      status = 422
    end

    render :json => response, :status => status
  end
end