module Limelight #:nodoc:

  # Include this module to get ACL functionality for root level documents.
  # @example Add ACL support to a document.
  #   require "limelight"
  #   class Person
  #     include Limelight::Acl
  #   end
  module Acl
    extend ActiveSupport::Concern

    included do
      field :permissions, :default => {}
    end

    # @example Check to see if the object with the given MongoId has a given permission on this document
    #   document.permission?
    #
    # @param [ Mongoid ] The MongoId of the object requesting permission
    # @param [ String ] The permission to check
    #
    # @return [ bool ]
    def permission?(object_id, permission)
      permissions and permissions.instance_of? BSON::OrderedHash and permissions.has_key?(permission.to_s) and permissions[permission.to_s].include?(object_id)
    end

    # @example Allow the given MongoId to edit & delete this document
    #   document.grant_owner
    #
    # @param [ Mongoid ] The MongoId of the object to grant ownership
    #
    # @return [ bool ]
    def grant_owner(object_id)
      self.grant_permission(object_id, "update")
      self.grant_permission(object_id, "destroy")
    end

    # @example Allow the given MongoId to edit this document
    #   document.grant_edit
    #
    # @param [ Mongoid ] The MongoId of the object to grant permission
    # @param [ String|Array ] The permission(s) to grant
    #
    # @return [ bool ]
    def grant_permission(object_id, permission)
      permission = [permission] unless permission.kind_of?(Array)

      permission.each do |p|
        self.permissions[p] ||= []
        self.permissions[p] << object_id unless self.permissions[p].include?(object_id)
      end
    end

    # @example Revoke the given permission(s) from this document
    #   document.revoke_permission
    #
    # @param [ Mongoid ] The MongoId of the object to revoke permission
    # @param [ String|Array ] The permission(s) to revoke
    #
    # @return [ bool ]
    def revoke_permission(object_id, permission)
      permission = [permission] unless permission.kind_of?(Array)

      permission.each do |p|
        if self.permissions[p]
          self.permissions[p].delete(object_id)
        end
      end
    end
  end

  # Include this module to enable image handling on a document
  # @example Add image handling.
  #   require "limelight"
  #   class Person
  #     include Limelight::Images
  #   end
  module Images
    extend ActiveSupport::Concern

    included do
      field :active_image_version, :default => 0
      field :remote_image_url
      field :images, :default => []

      attr_accessible :remote_image_url
    end

    def image_ratio(version=nil)
      return nil if self.class.name == 'User' && use_fb_image
      return nil if self.class.name == 'Topic' && use_freebase_image
      return nil if images.length == 0 || (version && images.length <= version)

      if version
        images[version]['w'].to_f / images[version]['h'].to_f
      else
        images[0]['w'].to_f / images[0]['h'].to_f
      end
    end

    def image_width(version=nil)
      return nil if self.class.name == 'User' && use_fb_image
      return nil if self.class.name == 'Topic' && use_freebase_image
      return nil if images.length == 0 || (version && images.length <= version)

      if version
        images[version]['w']
      else
        images[0]['w']
      end
    end

    def image_height(version=nil)
      return nil if self.class.name == 'User' && use_fb_image
      return nil if self.class.name == 'Topic' && use_freebase_image
      return nil if images.length == 0 || (version && images.length <= version)

      if version
        images[version]['h']
      else
        images[0]['h']
      end
    end

    def size_dimensions
      {:small => 75, :normal => 150, :large => 500}
    end

    def available_sizes
      [:small, :normal, :large]
    end

    def available_modes
      [:square, :fit]
    end

    def filepath
      if Rails.env.production?
        "http://res.cloudinary.com/0lmhydab/image"
      elsif Rails.env.staging?
        "http://res.cloudinary.com/xpgzvxkw/image"
      else
        "http://res.cloudinary.com/limelight/image"
      end
    end

    def current_filepath
      "#{filepath}/#{active_image_version}"
    end

    def image_url(mode, size=nil, version=nil, original=false)
      version = active_image_version unless version
      if self.class.name == 'User' && use_fb_image
        if mode == :square
          "#{filepath}/facebook/w_#{size_dimensions[size]},h_#{size_dimensions[size]},c_thumb,g_faces/#{fbuid}.jpg"
        else
          "#{filepath}/facebook/w_#{size_dimensions[size]}/#{fbuid}.jpg"
        end
      else
        if version == 0
          if self.class.name == 'User'
            if twitter_handle
              if mode == :square
                "#{filepath}/twitter_name/w_#{size_dimensions[size]},h_#{size_dimensions[size]},c_thumb,g_faces/#{twitter_handle}.jpg"
              else
                "#{filepath}/twitter_name/w_#{size_dimensions[size]}/#{fbuid}.jpg"
              end
            else
              "http://www.gravatar.com/avatar?d=mm&f=y&s=#{size_dimensions[size]}"
            end
          elsif self.class.name == 'Topic'
            if use_freebase_image
              "https://usercontent.googleapis.com/freebase/v1/image#{freebase_id}?maxheight=#{size_dimensions[size]}&maxwidth=#{size_dimensions[size]}&mode=#{mode == :fit ? 'fit' : 'fillcropmid'}&pad=true"
            else
              "http://img.p-li.me/defaults/topics/#{size}.gif"
            end
          end
        else
          if mode == :square
            "#{filepath}/upload/w_#{size_dimensions[size]},h_#{size_dimensions[size]},c_thumb,g_faces/#{id}_#{active_image_version}.jpg"
          else
            "#{filepath}/upload/w_#{size_dimensions[size]},c_fit/#{id}_#{active_image_version}.jpg"
          end

        end
      end
    end

    # Saves a new image from the remote_image_url currently specified on the model
    def save_remote_image(url)
      begin
        i = Magick::Image::read(url).first
      rescue => e
        return
      end

      begin
        Cloudinary::Uploader.upload(url, :public_id => "#{id}_#{self.images.length+1}")
      rescue => e
        return
      end

      self.images << {
              'remote_url' => url,
              'w' => i.columns,
              'h' => i.rows
      }

      self.active_image_version = self.images.length

      save
    end

    def process_images
      if !remote_image_url.blank? && active_image_version == 0
        save_remote_image(remote_image_url)
      end
    end
  end

  module Mentions
    extend ActiveSupport::Concern

    included do
      has_and_belongs_to_many :topic_mentions, :inverse_of => nil, :class_name => 'Topic'

      attr_accessor :topic_mention_names
      attr_accessible :topic_mention_ids, :topic_mention_names
    end

    def mentions_topic?(id)
      topic_mention_ids.include?(id)
    end

    #
    # SETTING MENTIONS
    #

    def set_mentions
      unless persisted?
        #set_user_mentions
        set_topic_mentions
      end
    end

    # Checks @content_raw for user mentions
    def set_user_mentions
      return unless content
      found_users = Array.new

      # Searches for strings following @username. Returns an array of usernames.
      content.scan(/\@([0-9a-zA-Z]*)/).each do |user|
        unless found_users.include? user[0]
          found_users << user[0].parameterize
        end
      end

      # Find the users
      self.user_mentions = User.where(:slug.in => found_users)
    end

    def set_topic_mentions
      save_new_topic_mentions(topic_mention_names) if topic_mention_names && topic_mention_names.length > 0
    end

    # takes an array of new topic names
    def save_new_topic_mentions(topic_mention_names)
      topics = Topic.search_or_create(topic_mention_names, user)
      topics.each do |t|
        add_topic_mention(t)
      end
    end

    def add_topic_mention(topic)
      return unless topic
      unless topic_mention_ids.include?(topic.id)
        self.topic_mention_ids << topic.id
        Resque.enqueue(PostAddTopic, self.id.to_s, topic.id.to_s)
        Neo4j.post_add_topic_mention(self, topic)
        Neo4j.update_talk_count(user, topic, 1, nil, nil, _parent.id)
        _parent.topic_ids << topic.id
        _parent.topic_ids.uniq!
      end
    end

    def remove_topic_mention(topic)
      return unless topic
      mention = self.topic_mention_ids.delete(topic.id)
      if mention
        FeedUserItem.unpush_post_through_topic(self, topic)
        Neo4j.post_remove_topic_mention(self, topic)
        Neo4j.update_talk_count(user, topic, -1, nil, nil, _parent.id)
        _parent.topic_ids.delete(topic.id)
        _parent.topic_ids.uniq!
      end
    end

    def reset_topics(topic_ids, topic_names)
      topic_ids = [] unless topic_ids && topic_ids.is_a?(Array)
      topic_names = [] unless topic_names && topic_names.is_a?(Array)

      topic_ids.uniq!
      topic_names.uniq!

      self.topic_mentions.each do |t|
        Neo4j.update_talk_count(user, t, -1, nil, nil, _parent.id)
      end
      self.topic_mention_ids = []

      topic_ids.each do |t|
        topic = Topic.find(t)
        if topic
          add_topic_mention(topic)
          Neo4j.update_talk_count(user, topic, 1, nil, nil, _parent.id)
        end
      end

      topic_names.each do |t|
        self.save_new_topic_mentions([t])
        topic = Topic.where("aliases.slug" => t.parameterize, "primary_type_id" => {"$exists" => false}).first
        Neo4j.update_talk_count(user, topic, 1, nil, nil, _parent.id) if topic
      end

      self.expire_cached_json
    end
  end

  # Include this module to get Throttling functionality for models.
  # @example Add ACL support to a document.
  #   require "limelight"
  #   class Person
  #     include Limelight::Throttle
  #   end
  module Throttle
    extend ActiveSupport::Concern

    included do
      validate :throttle_check
    end

    def throttle_check
      unless persisted? || user_id.to_s == User.limelight_user_id
        last = Kernel.const_get(self.class.name).where(:user_id => user_id).desc(:_id).first
        if last && Time.now - last.created_at < 10
          errors.add(:limited, "You must wait at least 10 seconds before posting again")
        end
      end
    end
  end
end
