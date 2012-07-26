class TestJob
  include Resque::Plugins::UniqueJob
  @queue = :fast

  def self.perform()
    PostMedia.all.each do |p|
      p.images.each_with_index do |i,k|
        begin
          Cloudinary::Uploader.upload(i['remote_url'], :public_id => "#{p.id}_#{k+1}")
        rescue => e
          p.images.delete_at(k)
          p.active_image_version = p.images.length
          p.save
        end
      end
    end

    Topic.all.each do |p|
      p.images.each_with_index do |i,k|
        begin
          Cloudinary::Uploader.upload(i['remote_url'], :public_id => "#{p.id}_#{k+1}")
        rescue => e
          p.images.delete_at(k)
          p.active_image_version = p.images.length
          p.save
        end
      end
    end
  end
end