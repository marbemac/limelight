class Link < PostMedia

  validate :has_valid_url
  validates :title, :presence => { :message => 'Post title cannot be blank.' }

end