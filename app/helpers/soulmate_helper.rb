module SoulmateHelper
  include Rails.application.routes.url_helpers

  def user_nugget(user)
    nugget = {
              'id' => user.id.to_s,
              'term' => user.username,
              'score' => user.score,
              'data' => {
                      'slug' => user.slug,
                      'url' => user_path(user)
              }
    }

    if user.first_name && !user.first_name.blank? && user.last_name && !user.last_name.blank?
      nugget['data']['name'] = user.fullname
      nugget['aliases'] = [user.fullname]
    end

    nugget
  end

  def topic_nugget(topic)
    nugget = {
              'id' => topic.id.to_s,
              'term' => topic.name,
              'score' => topic.score,
              'data' => {
                      'slug' => topic.slug,
                      'url' => topic_path(topic),
                      'ooac' => []
              }
    }

    if topic.aliases.length > 0
      nugget['aliases'] ||= Array.new
      topic.aliases.each do |data|
        nugget['aliases'] << data.name
        nugget['data']['ooac'] << data.name if data.ooac
      end
    end

    if topic.primary_type
      nugget['data']['type'] = topic.primary_type
    end

    if topic.short_name && !topic.short_name.blank?
      nugget['data']['short_name'] = topic.short_name
    end

    nugget
  end
end