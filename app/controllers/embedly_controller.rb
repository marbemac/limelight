class EmbedlyController < ApplicationController
  include EmbedlyHelper

  def show
    render :json => fetch_url(params[:url])
  end

end