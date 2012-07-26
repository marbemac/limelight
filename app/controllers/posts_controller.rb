class PostsController < ApplicationController
  before_filter :authenticate_user!, :only => [:create,:edit,:update,:destroy,:disable,:stream,:publish_share,:discard_share]
  include ModelUtilitiesHelper

  respond_to :json

  def index
    posts = PostMedia.find_by_params(params)

    render :json => posts
  end

  def publish_share
    post = PostMedia.unscoped.find(params[:id])
    if post

      if post.status == 'pending'
        post.title = params[:title]
      end

      if post.valid?
        share = post.get_share(current_user.id)

        if share
          share.reset_topics(params[:topic_mention_ids], params[:topic_mention_names])
          share.content = params[:comment]
        else
          share = post.add_share(current_user.id, params[:comment], params[:topic_ids], params[:topic_names])
        end
        share.status = 'active'

        post.reset_topic_ids
        post.status = 'active'
        post.save

        response = post.to_json(:properties => :public)
        response = Yajl::Parser.parse(response)
        response['share'] = Yajl::Parser.parse(share.to_json(:properties => :public))

        render :json => build_ajax_response(:ok, nil, "Shared Post Successfully", nil, nil, response), :status => 201
      else
        render :json => build_ajax_response(:error, nil, "Could not Publish Post.", post.errors, nil), :status => 400
      end
    else
      render :json => build_ajax_response(:error, nil, "Could not find post.'", nil, nil), :status => 404
    end
  end

  def discard_share
    post = PostMedia.unscoped.find(params[:id])
    if post

      post.delete_share(current_user.id)

      if post.status == 'pending' && post.shares.length == 0
        post.destroy
      else
        post.save
      end

      render :json => build_ajax_response(:ok, nil, "Share Discarded"), :status => 201

    else
      render :json => build_ajax_response(:error, nil, "Could not find post.'", nil, nil), :status => 404
    end
  end

  def publish
    authorize! :manage, :all

    post = PostMedia.unscoped.find(params[:id])
    if post
      post.title = params[:title] if params[:title]

      if post.valid?

        if params[:topic_mention_ids]
          topics = Topic.where(:_id => {"$in" => params[:topic_mention_ids]})
          topics.each do |t|
            post.topic_ids << t.id
          end
        end
        if params[:topic_mention_names]
          topics = Topic.search_or_create(params[:topic_mention_names], current_user)
          topics.each do |t|
            post.topic_ids << t.id
          end
        end
        post.topic_ids.uniq!
        post.status = 'publishing'
        post.update_shares_topics
        post.shares.each do |s|
          s.status = 'publishing'
        end

        if params[:remote_image_url]
          post.remote_image_url = params[:remote_image_url]
          post.process_images
        end

        post.save

        # publish it sometime in the next 6 hours
        Resque.enqueue_in(rand(21600), PostPublish, post.id.to_s)

        response = post.to_json(:properties => :public)
        response = Yajl::Parser.parse(response)

        render :json => build_ajax_response(:ok, nil, "Published Scheduled Successfully", nil, nil, response), :status => 201
      else
        render :json => build_ajax_response(:error, nil, "Could not Publish Post.", post.errors, nil), :status => 400
      end
    else
      render :json => build_ajax_response(:error, nil, "Could not find post.'", nil, nil), :status => 404
    end
  end

  def destroy
    authorize! :manage, :all

    post = PostMedia.unscoped.find(params[:id])
    if post
      post.destroy
      render :json => build_ajax_response(:ok, nil, "Deleted Post Successfully", nil), :status => 201
    else
      render :json => build_ajax_response(:error, nil, "Could not find post.'", nil, nil), :status => 404
    end
  end

end