class RegistrationsController < Devise::RegistrationsController

  # POST /resource
  # Is this used? Similar to UsersController create action
  def create
    params[:user] = {
            :username => params[:username],
            :email => params[:email],
            :password => params[:password]
    }
    build_resource
    resource.used_invite_code_id = Moped::BSON::ObjectId(session[:invite_code])

    if resource.save
      if resource.active_for_authentication?
        set_flash_message :notice, :signed_up if is_navigational_format?
        sign_in(resource_name, resource)
        track_mixpanel("Signup", resource.as_json)
        render json: build_ajax_response(:ok, after_sign_up_path_for(resource)), status: 201
      else
        set_flash_message :notice, :inactive_signed_up, :reason => inactive_reason(resource) if is_navigational_format?
        expire_session_data_after_sign_in!
        render json: build_ajax_response(:ok, after_inactive_sign_up_path_for(resource)), status: 201
      end
    else
      clean_up_passwords(resource)
      if resource.errors[:invite_code_id].blank?
        render json: build_ajax_response(:error, nil, nil, resource.errors), status: 422
      else
        render json: build_ajax_response(status, nil, "Your invite code is invalid!"), status: 422
      end
    end
  end

  protected

  def after_sign_up_path_for(resource)
    root_path
  end
  def after_inactive_sign_up_path_for(resource)
    root_path :show => 'confirm'
  end

end
