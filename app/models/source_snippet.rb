class SourceSnippet
  include Mongoid::Document

  field :name
  field :url
  field :video_id # for video submissions

  embedded_in :post_media

  def to_json
    {
        :name => name,
        :url => URI.escape(url),
        :video_id => video_id
    }
  end
end