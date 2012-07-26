class ApplicationController < ActionController::Base
  protect_from_forgery
  before_filter :init, :set_user_time_zone, :save_referer

  # Handle authorization exceptions
  rescue_from CanCan::AccessDenied do |exception|
    if signed_in?
      permission_denied(exception)
    else
      render_forbidden(exception)
    end
  end

  # Exception Throwers

  # Not Found (404)
  def not_found(message)
    @site_style = 'narrow'
    raise ActionController::RoutingError.new(message)
  end
  # Permission denied (401)
  def permission_denied(exception)
    if request.xhr?
      render json: {:status => :error, :message => "You don't have permission to #{exception.action} #{exception.subject.class.to_s.pluralize}"}, :status => 403
    else
      render :file => "public/401.html", :status => :unauthorized
    end
  end
  def render_forbidden(exception)
    if request.xhr?
      render json: {:status => :error, :message => "You must be logged in to do that!"}, :status => 401
    else
      session[:post_auth_path] = request.env['PATH_INFO']
      redirect_to new_user_session_path
    end
  end

  # Exception Handlers

  rescue_from ActionController::RoutingError do
    render :file => "public/404.html", :status => 404
  end

  # Redirect after sign in / sign up
  def after_sign_in_path_for(resource)
    back_or_default_path root_path
  end

  def back_or_default_path(default)
    path = session[:return_to] ? session[:return_to] : default
    session[:return_to] = nil
    path
  end

  def save_referer
    unless signed_in?
      unless session['referer']
        session['referer'] = request.referer || 'none'
      end
    end
  end

  # Mixpanel
  def track_mixpanel(name, params)
    Resque.enqueue(MixpanelTrackEvent, name, params, request.env.select{|k,v| v.is_a?(String) || v.is_a?(Numeric) })
  end

  def build_ajax_response(status, redirect=nil, flash=nil, errors=nil, extra=nil, object=nil)
    response = {:status => status, :event => "#{params[:controller]}_#{params[:action]}"}
    response[:redirect] = redirect if redirect
    response[:flash] = flash if flash
    response[:errors] = errors if errors
    response[:object] = object if object
    response.merge!(extra) if extra
    response
  end

  private

  # Used to display the page load time on each page
  def init
    @start_time = Time.now
  end

  def set_user_time_zone
    Time.zone = current_user.time_zone if signed_in? && current_user
    Chronic.time_class = Time.zone
  end

  # open graph tags
  def build_og_tags(title, type, url, image, desc, extra={})
    og_tags = []
    og_tags << ["og:title", title]
    og_tags << ["og:type", type]
    og_tags << ["og:url", url]
    og_tags << ["og:image", image] if image && !image.blank?
    og_tags << ["og:description", desc]
    extra.each do |k,e|
      og_tags << [k, e]
    end
    og_tags
  end
end
