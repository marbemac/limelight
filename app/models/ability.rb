class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new # guest user (not logged in)
    if user.role? 'admin'
      can :manage, :all
    else
      can :read, :all

      [Link, Picture, Video, Topic].each do |resource|
        can :create, resource if user.persisted?
      end

      # Uses the limelight ACL system
      [Link, Picture, Video, Topic].each do |resource|
        [:edit, :update, :destroy].each do |permission|
          can permission.to_sym, resource do |target|
            target.try(:permission?, user.id, permission)
          end
        end
      end
    end
  end
end
