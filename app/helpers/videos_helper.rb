module VideosHelper

  def video_id(provider, data)
    case provider.downcase
      when 'youtube'
        video_id = data[:payload][:video][:data][:id]
      when 'vimeo'
        video_id = data[:payload][:video_id]
      else
        video_id = nil
    end
    video_id
  end

  def video_embed(source, w, h, provider=nil, video_id=nil, embed_html=nil, autoplay=nil)
    autoplay = autoplay ? 'autoplay=1' : ''
    unless autoplay.blank?
      if embed_html.include? '?'
        autoplay = '&'+autoplay
      else
        autoplay = '?'+autoplay
      end
    end
    if embed_html && ((embed_html =~ /width/i) != nil)
      embed_html.gsub('\'', '"').gsub(/(width)="\d+"/, '\1="'+w.to_s+'"').gsub(/(height)="\d+"/, '\1="'+h.to_s+'"').gsub(/(src)="([^'"]*)"/, '\1="\2'+autoplay+'"').html_safe
    else
      "<p>Embed not available.</p>".html_safe
    end
  end

end