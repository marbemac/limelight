class UsersController < ApplicationController
  before_filter :authenticate_user!, :only => [:settings, :update, :picture_update, :update_settings, :topic_finder, :invite_by_email, :show_contacts]
  include ModelUtilitiesHelper

  respond_to :html, :json

  def show
    authorize! :manage, :all if params[:require_admin]

    if params[:slug]
      @this = User.where(:slug => params[:slug].parameterize).first
    else
      @this = params[:id] && params[:id] != "0" ? User.find_by_slug_id(params[:id]) : current_user
    end

    not_found("User not found") unless @this

    if params[:show_og] && params[:id] != "0"
      @title = @this.username
      @description = "#{@this.username} on Limelight."
      @og_tags = build_og_tags(@title, "#{og_namespace}:user", user_url(@this), @this.image_url(:fit, :large), @description, {"og:username" => @this.username, "#{og_namespace}:display_name" => "User", "#{og_namespace}:followers_count" => @this.followers_count.to_i, "#{og_namespace}:score" => @this.score.to_i, "#{og_namespace}:following_users" => @this.following_users_count.to_i, "#{og_namespace}:following_topics" => @this.following_topics_count.to_i})
    end

    respond_to do |format|
      format.html
      format.json { render :json => @this.as_json(:properties => :public) }
    end
  end

  def update
    # Post signup tutorial updates
    if params['tutorial_step'] && current_user.tutorial_step != params['tutorial_step']
      track_mixpanel("Signup Tutorial #{current_user.tutorial_step}", current_user.mixpanel_data)
      current_user.tutorial_step = params['tutorial_step']
    end
    current_user.tutorial1_step = params['tutorial1_step'] if params['tutorial1_step']

    current_user.email_comment = params[:email_comment] if params[:email_comment]
    current_user.email_mention = params[:email_mention] if params[:email_mention]
    current_user.email_follow = params[:email_follow] if params[:email_follow]
    current_user.weekly_email = params[:weekly_email] == "true" if params[:weekly_email]

    current_user.use_fb_image = params[:use_fb_image] == "true" if params[:use_fb_image]
    current_user.auto_follow_fb = params[:auto_follow_fb] == "true" if params[:auto_follow_fb]
    current_user.auto_follow_tw = params[:auto_follow_tw] == "true" if params[:auto_follow_tw]
    current_user.og_follows = params[:og_follows] == "true" if params[:og_follows]

    current_user.username = params[:username] if params[:username]
    current_user.unread_notification_count = params[:unread_notification_count] if params[:unread_notification_count]

    if current_user.changed?
      if current_user.save
        response = build_ajax_response(:ok, nil, "Setting updated")
        status = 200
      else
        response = build_ajax_response(:error, nil, nil, current_user.errors)
        status = :unprocessable_entity
      end
    else
      response = build_ajax_response(:error, nil, "Setting could not be changed. Please contact support@projectlimelight.com")
      status = :unprocessable_entity
    end

    render json: response, status: status
  end

  def update_network
    network = current_user.get_social_connect(params[:provider], params[:source])
    if network
      network.fetch_shares = params[:value] == "true" if params[:setting] == 'fetch_shares'
      network.fetch_likes = params[:value] == "true" if params[:setting] == 'fetch_likes'
      current_user.save
      response = build_ajax_response(:ok, nil, "Setting updated")
    else
      response = build_ajax_response(:error, nil, "You have not connected that network yet")
    end

    render :json => response
  end

  # get the topics a user is talking about
  def topics
    user = User.find_by_slug_id(params[:id])

    data = []
    topic_ids = Neo4j.user_topics(user.neo4j_id)
    topics = Topic.where(:_id => {"$in" => topic_ids})
    topics.each do |t|
      talk_count = Neo4j.user_topic_share_count(user.id, t.neo4j_id)
      data << {
          :topic => t,
          :count => talk_count
      }
    end

    render :json => data.sort_by{|d| d[:count] * -1}
  end

  # get the children a user is talking about of a certain topic
  def topic_children
    user = User.find_by_slug_id(params[:id])
    topic = Topic.find_by_slug_id(params[:topic_id])
    topic_ids = Neo4j.user_topic_children(user.id, topic.neo4j_id)
    topics = Topic.where(:_id => {"$in" => topic_ids}).to_a
    data = []
    topics.each do |t|
      talk_count = Neo4j.user_topic_share_count(user.id, t.neo4j_id)
      data << {
          :topic => t,
          :count => talk_count
      }
    end

    render :json => data.sort_by{|d| d[:count] * -1}
  end
end