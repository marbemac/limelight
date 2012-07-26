class Video < PostMedia
  include VideosHelper

  field :embed_html # video embeds

  validate :has_valid_url
  validates :title, :presence => true

  def name
    title
  end
end