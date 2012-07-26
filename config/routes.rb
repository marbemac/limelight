ProjectLimelight::Application.routes.draw do

  # redirect to example.com if user goes to www.example.com
  match '(*any)' => redirect { |p, req| req.url.sub('www.', '') }, :constraints => { :host => /^www\./ }

  get 'switch_user', :controller => 'switch_user', :action => 'set_current_user'

  # API
  scope 'api' do
    scope 'users' do
      get 'index' => 'users#index'
      get ':id/topics/:topic_id/children' => 'users#topic_children'
      get ':id/topics/:topic_id/parents' => 'users#topic_parents'
      get ':id/topics' => 'users#topics'
      put ':id/networks' => 'users#update_network'
      post '' => 'users#create'
      put '' => 'users#update'
      get ':id' => 'users#show'
    end

    scope 'topics' do
      scope ':id' do
        get 'children' => 'topics#children'
        get 'parents' => 'topics#parents'
        get '' => 'topics#show'
      end

      get '' => 'topics#index'
    end

    scope 'posts' do
      post '' => 'posts#create'
      post ':id/shares' => 'posts#publish_share'
      delete ':id/shares' => 'posts#discard_share'
      post ':id/publish' => 'posts#publish'
      delete ':id' => 'posts#destroy'
      get ':id' => 'posts#show'
      get '' => 'posts#index'
    end

    scope 'beta_signups' do
      post '' => 'beta_signups#create'
    end
  end

  resque_constraint = lambda do |request|
    request.env['warden'].authenticate? and request.env['warden'].user.role?('admin')
  end

  # Resque admin
  constraints resque_constraint do
    mount Resque::Server, :at => "admin/resque"
  end

  # Soulmate api
  mount Soulmate::Server, :at => "autocomplete"

  # Testing
  get 'testing' => 'testing#test', :as => :test

  # Embedly
  get 'embed' => 'embedly#show', :as => :embedly_fetch

  # Users
  devise_for :users, :skip => [:sessions], :controllers => { :omniauth_callbacks => "omniauth_callbacks",
                                           :registrations => :registrations,
                                           :confirmations => :confirmations,
                                           :sessions => :sessions }
end
