class TopicsController < ApplicationController
  include ModelUtilitiesHelper

  respond_to :html, :json

  def index
    topics = Topic.parse_filters(Topic.all, params)

    render :json => topics
  end

  def show
    # Doesn't use find_by_slug() because it doesn't work after Topic.unscoped (deleted topics are ignored)
    if params[:slug]
      @this = Topic.where(:slug_pretty => params[:slug].parameterize).first
    else
      @this = Topic.find_by_slug_id(params[:id])
    end

    not_found("Topic not found") unless @this
    authorize! :read, @this

    respond_to do |format|
      format.html do
        @title = @this.name
        @description = @this.summary ? @this.summary : "All posts about the #{@this.name} topic on Limelight."
        @og_tags = build_og_tags(@title, og_namespace+":topic", topic_url(@this), @this.image_url(:fit, :large), @description, {"#{og_namespace}:display_name" => "Topic", "#{og_namespace}:followers_count" => @this.followers_count.to_i, "#{og_namespace}:score" => @this.score.to_i, "#{og_namespace}:type" => @this.primary_type ? @this.primary_type : ''})
      end
      format.json { render :json => @this.to_json(:properties => :public) }
    end

  end

  def children
    topic = Topic.find_by_slug_id(params[:id])
    topic_ids = Neo4j.pull_from_ids(topic.neo4j_id, params[:depth] ? params[:depth] : 1).to_a
    topics = Topic.where(:_id => {"$in" => topic_ids})
    topics = Topic.parse_filters(topics, params)
    render :json => topics
  end

  def parents
    topic = Topic.find_by_slug_id(params[:id])
    topic_ids = Neo4j.pulled_from_ids(topic.neo4j_id, params[:depth] ? params[:depth] : 20).to_a
    topics = Topic.where(:_id => {"$in" => topic_ids})
    topics = Topic.parse_filters(topics, params)
    render :json => topics
  end
end