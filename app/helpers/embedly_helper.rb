module EmbedlyHelper
  include VideosHelper
  include ApplicationHelper
  include ActionView::Helpers::DateHelper

  def fetch_url(url)
    response = {
        :type => 'Link',
        :video => nil,
        :photo => nil,
        :images => [],
        :provider_name => [],
        :url => url,
        :title => [],
        :existing => nil,
        :only_picture => false,
        :topic_suggestions => [],
        :description => nil
    }

    # check if it's an image
    begin
      str = open(url)
    rescue
      return nil
    end
    if str && str.content_type.include?('image')
      response[:type] = 'Picture'
      response[:images] = [{:url => url}]
      response[:only_picture] = true
    else
      embedly_key = 'ca77b5aae56d11e0a9544040d3dc5c07'
      begin
        buffer = open("http://api.embed.ly/1/preview?key=#{embedly_key}&url=#{CGI.escape(url)}&format=json", "UserAgent" => "Ruby-Wget").read
      rescue
        return nil
      end

      # convert JSON data into a hash
      result = JSON.parse(buffer)

      # clean images (discard small ones)
      clean_images = []
      result['images'].each do |i|
        if i['width'] >= 200
          clean_images << i
        end
      end

      response[:images] = clean_images
      response[:provider_name] = result['provider_name']
      response[:url] = result['url']
      response[:title] = result['title']
      response[:description] = result['description']

      if result['object']
        if result['object']['type'] == 'video'
          response[:type] = 'Video'
          response[:video] = video_embed(nil, 120, 120, result['provider_name'], nil, result['object']['html'])
        elsif result['object']['type'] == 'photo'
          response[:type] = 'Picture'
          response[:photo] = result['object']['url']
        end
      end
    end

    post = result && result['url'] ? PostMedia.unscoped.where('sources.url' => result['url']).first : nil
    if post
      response[:existing] = post
    elsif !response[:only_picture]
      response[:topic_suggestions] = Topic.suggestions_by_url(result['url'], result['title'])
    end

    response
  end
end