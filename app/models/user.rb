class User
  include Mongoid::Document
  include Mongoid::Paranoia
  include Mongoid::Timestamps
  include Mongoid::CachedJson
  include Limelight::Images
  include ModelUtilitiesHelper

  @marc_id = "4eb9cda1cddc7f4068000042"
  @matt_id = "4ebf1748cddc7f0c9f000002"
  @limelight_user_id = "4f971b6ccddc7f1480000046"
  class << self; attr_accessor :marc_id, :matt_id, :limelight_user_id end

  # Include default devise modules. Others available are:
  # :token_authenticatable, :encryptable, :confirmable, :lockable, :timeoutable
  devise :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :trackable, :validatable, :omniauthable, :token_authenticatable

  ## Database authenticatable
  field :encrypted_password, :type => String

  ## Trackable
  field :sign_in_count,      :type => Integer
  field :current_sign_in_at, :type => Time
  field :last_sign_in_at,    :type => Time
  field :current_sign_in_ip, :type => String
  field :last_sign_in_ip,    :type => String

  # Token authenticatable
  field :authentication_token, :type => String

  ## Confirmable
  field :confirmation_token,   :type => String
  field :confirmed_at,         :type => Time
  field :confirmation_sent_at, :type => Time
  #field :unconfirmed_email,    :type => String # Only if using reconfirmable

  ## Rememberable
  field :remember_created_at, :type => Time

  field :username
  field :username_reset, :default => false # when this is true the user can change their username
  field :slug
  field :name
  field :status, :default => 'active'
  field :email
  field :gender
  field :birthday, :type => Date
  field :time_zone, :type => String, :default => "Eastern Time (US & Canada)"
  field :roles, :default => []
  field :share_count, :default => 0
  field :bio
  field :use_fb_image, :default => false
  field :origin # what did the user use to originally signup (limelight, facebook, etc)
  field :neo4j_id, :type => Integer
  field :stub_user, :default => false
  field :twitter_handle
  field :latest_tweet_id, :default => 1

  embeds_many :social_connects

  has_many :post_media, :class_name => 'PostMedia'
  has_many :topics
  has_many :topic_connections

  attr_accessor :login
  attr_accessible :username, :name, :email, :password, :password_confirmation, :remember_me,
                  :login, :bio, :stub_user, :twitter_handle

  with_options :if => :is_active? do |user|
    user.validates :username, :uniqueness => { :case_sensitive => false, :message => 'Username is already taken' },
              :length => { :minimum => 3, :maximum => 15, :message => 'Username must be between 3 and 15 characters' },
              :format => { :with => /\A[a-zA-Z_0-9]+\z/, :message => "Username can only contain letters, numbers, and underscores" },
              :format => { :with => /^[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)*$/, :message => "Username must start with a letter and end with a letter or number" }
    user.validates :email, :uniqueness => { :case_sensitive => false, :message => 'This email has already been used' }
    user.validates :bio, :length => { :maximum => 150, :message => 'Bio has a max length of 150' }
    user.validate :username_change
  end

  before_create :neo4j_create, :generate_slug
  after_create :add_to_soulmate, :save_profile_image, :send_personal_email
  before_update :update_slug
  after_update :update_denorms
  before_destroy :remove_from_soulmate, :disconnect

  index({ :slug => 1 })
  index({ :email => 1 })
  index({ "social_connects" => 1 })

  # Return the users username instead of their ID
  def to_param
    username
  end

  def generate_slug
    self.slug = username.parameterize
  end

  def update_slug
    if username_changed?
      generate_slug
    end
  end

  def is_active?
    status == 'active' && !stub_user
  end

  # after destroy, various cleanup
  def disconnect
    # remove this users shares
    posts = PostMedia.where("shares.user_id" => id)
    posts.each do |p|
      p.delete_share(id)
      if p.shares.length == 0
        p.destroy
      else
        p.save
      end
    end
  end

  # Use FB image if logged in with FB
  def save_profile_image
    facebook = get_social_connect 'facebook'
    if facebook
      self.use_fb_image = true
      save
    end
  end

  def username_change
    if username_was && username_changed? && username_was != username
      if username_reset == false && !role?('admin')
        errors.add(:username, "Username cannot be changed right now")
      else
        self.username_reset = false
      end
    end
  end

  ###
  # ROLES
  ###

  # Checks to see if this user has a given role
  def role?(role)
    self.roles.include? role
  end

  # Adds a role to this user
  def grant_role(role)
    self.roles << role unless self.roles.include?(role)
  end

  # Removes a role from this user
  def revoke_role(role)
    if self.roles
      self.roles.delete(role)
    end
  end

  def name_or_username
    if name then name else username end
  end

  def add_to_soulmate
    Resque.enqueue(SmCreateUser, id.to_s) unless stub_user
  end

  def remove_from_soulmate
    Resque.enqueue(SmDestroyUser, id.to_s)
  end

  def send_welcome_email
    UserMailer.welcome_email(self.id.to_s).deliver
    UserMailer.welcome_email_admins(self.id.to_s).deliver
  end

  def send_personal_email
    hour = Time.now.hour
    variation = rand(7200)
    if hour < 11
      delay = Chronic.parse('Today at 11AM').to_i - Time.now.utc.to_i + variation
      Resque.enqueue_in(delay, SendPersonalWelcome, id.to_s, "today")
    elsif hour >= 11 && hour < 18
      Resque.enqueue_in(1.hours + variation, SendPersonalWelcome, id.to_s, "today")
    else
      delay = Chronic.parse('Tomorrow at 11AM').to_i - Time.now.utc.to_i + variation
      Resque.enqueue_in(delay, SendPersonalWelcome, id.to_s, "today")
    end
  end

  def get_social_connect(provider)
    social_connects.detect{|s| s.provider == provider }
  end

  def fbuid
    facebook = get_social_connect('facebook')
    facebook.uid if facebook
  end

  def twuid
    twitter = get_social_connect('twitter')
    twitter.uid if twitter
  end

  def facebook
    connection = get_social_connect('facebook')
    @fb_user ||= Koala::Facebook::API.new(connection.token) if connection
  end

  def twitter
    provider = get_social_connect('twitter')
    if provider
      @twitter ||= Twitter.configure do |config|
        config.consumer_key = ENV['TWITTER_KEY']
        config.consumer_secret = ENV['TWITTER_SECRET']
        config.oauth_token = provider.token
        config.oauth_token_secret = provider.secret
      end
    end
  end

  def tweet_stream
    provider = get_social_connect('twitter')
    if provider
      @tweet_stream ||= TweetStream.configure do |config|
        config.consumer_key = ENV['TWITTER_KEY']
        config.consumer_secret = ENV['TWITTER_SECRET']
        config.oauth_token = provider.token
        config.oauth_token_secret = provider.secret
      end
      TweetStream::Client.new
    end
  end

  def neo4j_create
    node = Neo4j.neo.create_node(
            'uuid' => id.to_s,
            'type' => 'user',
            'username' => username,
            'created_at' => created_at.to_i
    )
    Neo4j.neo.add_node_to_index('users', 'uuid', id.to_s, node)
    self.neo4j_id = Neo4j.parse_id(node['self'])
    node
  end

  def neo4j_update
    node = Neo4j.neo.get_node_index('users', 'uuid', id.to_s)
    Neo4j.neo.set_node_properties(node, {'username' => username}) if node
  end

  ##########
  # JSON
  ##########

  def mixpanel_data(extra=nil)
    {
            :distinct_id => id.to_s,
            "User#{extra if extra} Username" => username,
            "User#{extra if extra} Birthday" => birthday,
            "User#{extra if extra} Connected Twitter?" => twuid ? true : false,
            "User#{extra if extra} Connected Facebook?" => fbuid ? true : false,
            "User#{extra if extra} Origin" => origin,
            "User#{extra if extra} Status" => status,
            "User#{extra if extra} Sign Ins" => sign_in_count,
            "User#{extra if extra} Last Sign In" => current_sign_in_at,
            "User#{extra if extra} Created At" => created_at,
            "User#{extra if extra} Confirmed At" => confirmed_at
    }
  end

  json_fields \
    :_id => { :properties => :short, :versions => [ :v1 ] },
    :id => { :definition => :username, :properties => :short, :versions => [ :v1 ] },
    :type => { :definition => lambda { |instance| 'User' }, :properties => :short, :versions => [ :v1 ] },
    :username => { :properties => :short, :versions => [ :v1 ] },
    :name => { :properties => :short, :versions => [ :v1 ] },
    :share_count => { :properties => :short, :versions => [ :v1 ] },
    :images => { :definition => lambda { |instance| User.json_images(instance) }, :properties => :short, :versions => [ :v1 ] },
    :status => { :properties => :short, :versions => [ :v1 ] },
    :url => { :definition => lambda { |instance| "/users/#{instance.to_param}" }, :properties => :short, :versions => [ :v1 ] },
    :created_at => { :definition => lambda { |instance| instance.created_at.to_i }, :properties => :short, :versions => [ :v1 ] },
    :facebook_id => { :definition => :fbuid, :properties => :short, :versions => [ :v1 ] },
    :twitter_id => { :definition => :twuid, :properties => :short, :versions => [ :v1 ] },
    :twitter_handle => { :properties => :short, :versions => [ :v1 ] },
    :roles => { :properties => :short, :versions => [ :v1 ] },
    :username_reset => { :properties => :public, :versions => [ :v1 ] }

  class << self

    def json_images(model)
      {
        :ratio => model.image_ratio,
        :w => model.image_width,
        :h => model.image_height,
        :original => model.image_url(nil, nil, nil, true),
        :fit => {
          :large => model.image_url(:fit, :large),
          :normal => model.image_url(:fit, :normal),
          :small => model.image_url(:fit, :small)
        },
        :square => {
          :large => model.image_url(:square, :large),
          :normal => model.image_url(:square, :normal),
          :small => model.image_url(:square, :small)
        }
      }
    end

  ##########
  # END JSON
  ##########

    # find a user by slug or id
    def find_by_slug_id(id)
      if Moped::BSON::ObjectId.legal?(id)
        User.find(id)
      else
        User.where(:slug => id.parameterize).first
      end
    end

    # Omniauth providers
    def find_by_omniauth(omniauth, signed_in_resource=nil, invite_code=nil, request_env=nil, source='Limelight')
      new_user = false
      login = false
      info = omniauth['info']
      extra = omniauth['extra']['raw_info']

      existing_user = User.where("social_connects.uid" => omniauth['uid'], 'social_connects.provider' => omniauth['provider'], 'social_connects.source' => source).first
      # Try to get via email if user not found and email provided
      unless existing_user || !info['email']
        existing_user = User.where(:email => info['email']).first
      end

      if signed_in_resource && existing_user && signed_in_resource != existing_user
        user = signed_in_resource
        user.errors[:base] << "There is already a user with that account"
        return user
      elsif signed_in_resource
        user = signed_in_resource
      elsif existing_user
        user = existing_user
      end

      invite = invite_code ? InviteCode.find(invite_code) : nil

      # If we found the user, update their token
      if user
        connect = user.social_connects.detect{|connection| connection.uid == omniauth['uid'] && connection.provider == omniauth['provider'] && connection.source == source}
        # Is this a new connection?
        unless connect
          new_connect = true
          connect = SocialConnect.new(:uid => omniauth["uid"], :provider => omniauth['provider'], :image => info['image'], :source => source)
          connect.secret = omniauth['credentials']['secret'] if omniauth['credentials'].has_key?('secret')

          user.social_connects << connect
          user.use_fb_image = true if omniauth['provider'] == 'facebook' && user.images.length == 0
        end
        # Update the token
        connect.token = omniauth['credentials']['token']

        unless signed_in_resource
          login = true
        end

        # If an invite code is in the session, create a new user with a stub password.
      elsif (invite && invite.usable?) || source == 'ThisThat'
        new_user = true
        new_connect = true
        if extra["gender"] && !extra["gender"].blank?
          gender = extra["gender"] == 'male' || extra["gender"] == 'm' ? 'm' : 'f'
        else
          gender = nil
        end

        username = ""
        #username = info['nickname'].gsub(/[^a-zA-Z0-9]/, '')
        #existing_username = User.where(:slug => username).first
        #if existing_username
        #  username += Random.rand(99).to_s
        #end

        user = User.new(
            :username => username, :used_invite_code_id => invite.id,
            :first_name => extra["first_name"], :last_name => extra["last_name"],
            :gender => gender, :email => info["email"], :password => Devise.friendly_token[0,20]
        )
        user.username_reset = true
        user.birthday = Chronic.parse(extra["birthday"]) if extra["birthday"]
        connect = SocialConnect.new(:uid => omniauth["uid"], :provider => omniauth['provider'], :token => omniauth['credentials']['token'], :source => source)
        connect.secret = omniauth['credentials']['secret'] if omniauth['credentials'].has_key?('secret')
        user.social_connects << connect
        user.origin = omniauth['provider']
        user.use_fb_image = true if user.images.length == 0
      end

      if user && !user.confirmed?
        user.confirm!
        user.send_welcome_email
      end

      user.slug = user.id.to_s if new_user # set a temporary slug
      user.save :validate => false if user

      # update the users primary twitter handle
      if new_connect && connect.provider == 'twitter'
        begin
          user.twitter_handle = twitter.current_user.screen_name
        rescue => e
        end
      end

      if user && new_connect && source == 'Limelight'
        Resque.enqueue(AutoFollow, user.id.to_s, connect.provider.to_s) unless user.username.blank?

        if connect.provider == 'facebook'
          Resque.enqueue(AutoFollowFBLikes, user.id.to_s)
        end
      end

      if new_user && request_env
        Resque.enqueue(MixpanelTrackEvent, "Signup", user.mixpanel_data, request_env.select{|k,v| v.is_a?(String) || v.is_a?(Numeric) })
      end

      if login == true && request_env
        Resque.enqueue(MixpanelTrackEvent, "Login", user.mixpanel_data.merge!("Login Method" => omniauth['provider']), request_env.select{|k,v| v.is_a?(String) || v.is_a?(Numeric) })
      end

      user
    end
  end

  def find_for_database_authentication(conditions)
    login = conditions.delete(:login)
    self.any_of({ :slug => login.downcase.strip }, { :email => login.downcase.strip }).first
  end

  protected

  # Devise hacks for stub users
  def password_required?
    is_active? && (!persisted? || !password.nil? || !password_confirmation.nil?)
  end

  def email_required?
    is_active?
  end

  def update_denorms
    if username_changed? || status_changed?
      neo4j_update
      Resque.enqueue(SmCreateUser, id.to_s)
    end
  end

end