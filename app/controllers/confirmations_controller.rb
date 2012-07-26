class ConfirmationsController < Devise::ConfirmationsController

  # GET /resource/confirmation?confirmation_token=abcdef
  def show
    self.resource = resource_class.confirm_by_token(params[:confirmation_token])

    if resource.errors.empty?
      track_mixpanel("Confirm Signup", resource.mixpanel_data)
      resource.send_welcome_email
      #set_flash_message(:notice, :confirmed) if is_navigational_format?
      sign_in(resource_name, resource)
      respond_with_navigational(resource){ redirect_to after_confirmation_path_for(resource_name, resource) }
    else
      respond_with_navigational(resource.errors, :status => :unprocessable_entity){ redirect_to root_path :show => 'login' }
    end
  end

  protected

  # The path used after confirmation (will be post-reg).
  def after_confirmation_path_for(resource_name, resource)
    after_sign_in_path_for(resource)
  end

end
