module ApplicationHelper

  # Return a title on a per-page basis.
  def title
    base_title = "Limelight"
    title = truncate(@title, :length => 60, :separator => ' ')
    if @title.nil?
      base_title
    else
      "#{title} | #{base_title}"
    end
  end

  def description
    @description.nil? ? "" : @description
  end

  # Return the page load time (defined in application_controller.rb init)
  def load_time
    "#{(Time.now-@start_time).round(4)}s"
  end

  def output_errors(errors)
    error_string = ''
    errors.each do |field_name, error|
      error_string += "<div class='error'>#{field_name} #{error}</div>"
    end
    unless error_string.blank?
      "<div class='errors'>#{error_string}</div>".html_safe
    end
  end

  def parse_mentions(obj_text, object, absolute=false)
    return unless obj_text

    text = obj_text.dup
    # Loop through all of the topic mentions in the content
    text.scan(/\#\[([0-9a-zA-Z]+)#([a-zA-Z0-9,!\-_:'&\?\$ ]+)\]/).each do |topic|
      # Loop through all of the topic mentions connected to this object
      # If we found a match, replace the mention with a link to the topic
      topic_mention = object.topic_mentions.detect{|m| m.id.to_s == topic[0]}
      if topic_mention
        if absolute
          text.gsub!(/\#\[#{topic[0]}##{topic[1]}\]/, "<a href='#{topic_url(topic_mention)}'>#{topic[1]}</a>")
        else
          text.gsub!(/\#\[#{topic[0]}##{topic[1]}\]/, "#{topic_link(topic_mention, topic[1])}")
        end
      else
        text.gsub!(/\#\[#{topic[0]}##{topic[1]}\]/, topic[1])
      end
    end

    # Loop through all of the user mentions in the content
    text.scan(/\@\[([0-9a-zA-Z]+)#([\w ]+)\]/).each do |user|
      # Loop through all of the user mentions connected to this object
      # If we found a match, replace the mention with a link to the user
      user_mention = object.user_mentions.detect{|m| m.id.to_s == user[0]}
      if user_mention
        if absolute
          text.gsub!(/\@\[#{user[0]}##{user[1]}\]/, "<a href='#{user_url(user_mention)}'>#{user_mention.username}</a>")
        else
          text.gsub!(/\@\[#{user[0]}##{user[1]}\]/, "#{user_link(user_mention)}")
        end
      else
        text.gsub!(/\@\[#{user[0]}##{user[1]}\]/, user_mention.username)
      end
    end

    # Loop through all of the topic short names in the content
    text.scan(/\#([0-9a-zA-Z&]+)/).each do |topic|
      # Loop through all of the topic mentions connected to this object
      # If we found a match, replace the mention with a link to the topic
      topic_mention = object.topic_mentions.detect{|m| m.short_name == topic[0]}
      if topic_mention
        if absolute
          text.gsub!(/\##{topic[0]}/, "[##{topic[0]}](#{topic_url(topic_mention)})")
        else
          text.gsub!(/\##{topic[0]}/, "[##{topic[0]}](#{topic_path(topic_mention)})")
        end
      else
        text.gsub!(/\##{topic[0]}/, topic[0])
      end
    end

    # Replace any messed up mentions DOES NOT WORK RIGHT NOW
    #text.gsub!(/\[([^\]]*)\]/, "\\1")

    # Replace any messed up short names
    #text.gsub!(/\#([a-zA-Z0-9]*)/, "\\1")

    text.html_safe
  end

  def show_more(text, length)
    if text.length > length
      "<div class='show-more'>#{text[0...length]}<span class='extra hide'>#{text[length..text.length]}</span><div class='more'>... show more</div></div>".html_safe
    else
      text
    end
  end

  # Devise helper
  # https://github.com/plataformatec/devise/wiki/How-To:-Display-a-custom-sign_in-form-anywhere-in-your-app
  def resource_name
    :user
  end

  # Devise helper
  def resource
    @resource ||= User.new
  end

  # Devise helper
  def devise_mapping
    @devise_mapping ||= Devise.mappings[:user]
  end

  def pretty_time(date)
    pretty = time_ago_in_words(date, false).sub('about', '')+ ' ago'
    pretty == 'Today ago' ? 'just now' : pretty
  end
end