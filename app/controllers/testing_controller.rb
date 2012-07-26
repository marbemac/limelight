require "net/http"
include EmbedlyHelper

class TestingController < ApplicationController

  def test

    authorize! :manage, :all

    #post = PostMedia.first
    #foo = 'bar'
    #post.set_base_scores
    #PullTweets.perform
    #@count1 = 0
    #@count2 = 0

    PullTweets.perform
  end

end