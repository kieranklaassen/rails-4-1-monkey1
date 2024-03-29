require "cases/helper"
require 'models/post'
require 'models/tagging'
require 'models/tag'
require 'models/comment'
require 'models/author'
require 'models/essay'
require 'models/category'
require 'models/company'
require 'models/person'
require 'models/reader'
require 'models/owner'
require 'models/pet'
require 'models/reference'
require 'models/job'
require 'models/subscriber'
require 'models/subscription'
require 'models/book'
require 'models/developer'
require 'models/project'
require 'models/member'
require 'models/membership'
require 'models/club'
require 'models/categorization'
require 'models/sponsor'

class EagerAssociationTest < ActiveRecord::TestCase
  fixtures :posts, :comments, :authors, :essays, :author_addresses, :categories, :categories_posts,
            :companies, :accounts, :tags, :taggings, :people, :readers, :categorizations,
            :owners, :pets, :author_favorites, :jobs, :references, :subscribers, :subscriptions, :books,
            :developers, :projects, :developers_projects, :members, :memberships, :clubs, :sponsors

  def test_eager_with_has_one_through_join_model_with_conditions_on_the_through
    member = Member.all.merge!(:includes => :favourite_club).find(members(:some_other_guy).id)
    assert_nil member.favourite_club
  end

  def test_loading_with_one_association
    posts = Post.all.merge!(:includes => :comments).to_a
    post = posts.find { |p| p.id == 1 }
    assert_equal 2, post.comments.size
    assert post.comments.include?(comments(:greetings))

    post = Post.all.merge!(:includes => :comments, :where => "posts.title = 'Welcome to the weblog'").first
    assert_equal 2, post.comments.size
    assert post.comments.include?(comments(:greetings))

    posts = Post.all.merge!(:includes => :last_comment).to_a
    post = posts.find { |p| p.id == 1 }
    assert_equal Post.find(1).last_comment, post.last_comment
  end

  def test_loading_with_one_association_with_non_preload
    posts = Post.all.merge!(:includes => :last_comment, :order => 'comments.id DESC').to_a
    post = posts.find { |p| p.id == 1 }
    assert_equal Post.find(1).last_comment, post.last_comment
  end

  def test_loading_conditions_with_or
    posts = authors(:david).posts.references(:comments).merge(
      :includes => :comments,
      :where => "comments.body like 'Normal%' OR comments.#{QUOTED_TYPE} = 'SpecialComment'"
    ).to_a
    assert_nil posts.detect { |p| p.author_id != authors(:david).id },
      "expected to find only david's posts"
  end

  def test_with_ordering
    list = Post.all.merge!(:includes => :comments, :order => "posts.id DESC").to_a
    [:other_by_mary, :other_by_bob, :misc_by_mary, :misc_by_bob, :eager_other,
     :sti_habtm, :sti_post_and_comments, :sti_comments, :authorless, :thinking, :welcome
    ].each_with_index do |post, index|
      assert_equal posts(post), list[index]
    end
  end

  def test_has_many_through_with_order
    authors = Author.includes(:favorite_authors).to_a
    assert_no_queries { authors.map(&:favorite_authors) }
  end

  def test_with_two_tables_in_from_without_getting_double_quoted
    posts = Post.select("posts.*").from("authors, posts").eager_load(:comments).where("posts.author_id = authors.id").order("posts.id").to_a
    assert_equal 2, posts.first.comments.size
  end

  def test_loading_with_multiple_associations
    posts = Post.all.merge!(:includes => [ :comments, :author, :categories ], :order => "posts.id").to_a
    assert_equal 2, posts.first.comments.size
    assert_equal 2, posts.first.categories.size
    assert posts.first.comments.include?(comments(:greetings))
  end

  def test_duplicate_middle_objects
    comments = Comment.all.merge!(:where => 'post_id = 1', :includes => [:post => :author]).to_a
    assert_no_queries do
      comments.each {|comment| comment.post.author.name}
    end
  end

  def test_preloading_has_many_in_multiple_queries_with_more_ids_than_database_can_handle
    Comment.connection.expects(:in_clause_length).at_least_once.returns(5)
    posts = Post.all.merge!(:includes=>:comments).to_a
    assert_equal 11, posts.size
  end

  def test_preloading_has_many_in_one_queries_when_database_has_no_limit_on_ids_it_can_handle
    Comment.connection.expects(:in_clause_length).at_least_once.returns(nil)
    posts = Post.all.merge!(:includes=>:comments).to_a
    assert_equal 11, posts.size
  end

  def test_preloading_habtm_in_multiple_queries_with_more_ids_than_database_can_handle
    Comment.connection.expects(:in_clause_length).at_least_once.returns(5)
    posts = Post.all.merge!(:includes=>:categories).to_a
    assert_equal 11, posts.size
  end

  def test_preloading_habtm_in_one_queries_when_database_has_no_limit_on_ids_it_can_handle
    Comment.connection.expects(:in_clause_length).at_least_once.returns(nil)
    posts = Post.all.merge!(:includes=>:categories).to_a
    assert_equal 11, posts.size
  end

  def test_load_associated_records_in_one_query_when_adapter_has_no_limit
    Comment.connection.expects(:in_clause_length).at_least_once.returns(nil)

    post = posts(:welcome)
    assert_queries(2) do
      Post.includes(:comments).where(:id => post.id).to_a
    end
  end

  def test_load_associated_records_in_several_queries_when_many_ids_passed
    Comment.connection.expects(:in_clause_length).at_least_once.returns(1)

    post1, post2 = posts(:welcome), posts(:thinking)
    assert_queries(3) do
      Post.includes(:comments).where(:id => [post1.id, post2.id]).to_a
    end
  end

  def test_load_associated_records_in_one_query_when_a_few_ids_passed
    Comment.connection.expects(:in_clause_length).at_least_once.returns(3)

    post = posts(:welcome)
    assert_queries(2) do
      Post.includes(:comments).where(:id => post.id).to_a
    end
  end

  def test_including_duplicate_objects_from_belongs_to
    popular_post = Post.create!(:title => 'foo', :body => "I like cars!")
    comment = popular_post.comments.create!(:body => "lol")
    popular_post.readers.create!(:person => people(:michael))
    popular_post.readers.create!(:person => people(:david))

    readers = Reader.all.merge!(:where => ["post_id = ?", popular_post.id],
                                :includes => {:post => :comments}).to_a
    readers.each do |reader|
      assert_equal [comment], reader.post.comments
    end
  end

  def test_including_duplicate_objects_from_has_many
    car_post = Post.create!(:title => 'foo', :body => "I like cars!")
    car_post.categories << categories(:general)
    car_post.categories << categories(:technology)

    comment = car_post.comments.create!(:body => "hmm")
    categories = Category.all.merge!(:where => { 'posts.id' => car_post.id },
                                 :includes => {:posts => :comments}).to_a
    categories.each do |category|
      assert_equal [comment], category.posts[0].comments
    end
  end

  def test_associations_loaded_for_all_records
    post = Post.create!(:title => 'foo', :body => "I like cars!")
    SpecialComment.create!(:body => 'Come on!', :post => post)
    first_category = Category.create! :name => 'First!', :posts => [post]
    second_category = Category.create! :name => 'Second!', :posts => [post]

    categories = Category.where(:id => [first_category.id, second_category.id]).includes(:posts => :special_comments)
    assert_equal categories.map { |category| category.posts.first.special_comments.loaded? }, [true, true]
  end

  def test_finding_with_includes_on_has_many_association_with_same_include_includes_only_once
    author_id = authors(:david).id
    author = assert_queries(3) { Author.all.merge!(:includes => {:posts_with_comments => :comments}).find(author_id) } # find the author, then find the posts, then find the comments
    author.posts_with_comments.each do |post_with_comments|
      assert_equal post_with_comments.comments.length, post_with_comments.comments.count
      assert_nil post_with_comments.comments.to_a.uniq!
    end
  end

  def test_finding_with_includes_on_has_one_association_with_same_include_includes_only_once
    author = authors(:david)
    post = author.post_about_thinking_with_last_comment
    last_comment = post.last_comment
    author = assert_queries(3) { Author.all.merge!(:includes => {:post_about_thinking_with_last_comment => :last_comment}).find(author.id)} # find the author, then find the posts, then find the comments
    assert_no_queries do
      assert_equal post, author.post_about_thinking_with_last_comment
      assert_equal last_comment, author.post_about_thinking_with_last_comment.last_comment
    end
  end

  def test_finding_with_includes_on_belongs_to_association_with_same_include_includes_only_once
    post = posts(:welcome)
    author = post.author
    author_address = author.author_address
    post = assert_queries(3) { Post.all.merge!(:includes => {:author_with_address => :author_address}).find(post.id) } # find the post, then find the author, then find the address
    assert_no_queries do
      assert_equal author, post.author_with_address
      assert_equal author_address, post.author_with_address.author_address
    end
  end

  def test_finding_with_includes_on_null_belongs_to_association_with_same_include_includes_only_once
    post = posts(:welcome)
    post.update!(author: nil)
    post = assert_queries(1) { Post.all.merge!(includes: {author_with_address: :author_address}).find(post.id) }
    # find the post, then find the author which is null so no query for the author or address
    assert_no_queries do
      assert_equal nil, post.author_with_address
    end
  end

  def test_finding_with_includes_on_null_belongs_to_polymorphic_association
    sponsor = sponsors(:moustache_club_sponsor_for_groucho)
    sponsor.update!(sponsorable: nil)
    sponsor = assert_queries(1) { Sponsor.all.merge!(:includes => :sponsorable).find(sponsor.id) }
    assert_no_queries do
      assert_equal nil, sponsor.sponsorable
    end
  end

  def test_finding_with_includes_on_empty_polymorphic_type_column
    sponsor = sponsors(:moustache_club_sponsor_for_groucho)
    sponsor.update!(sponsorable_type: '', sponsorable_id: nil) # sponsorable_type column might be declared NOT NULL
    sponsor = assert_queries(1) do
      assert_nothing_raised { Sponsor.all.merge!(:includes => :sponsorable).find(sponsor.id) }
    end
    assert_no_queries do
      assert_equal nil, sponsor.sponsorable
    end
  end

  def test_loading_from_an_association
    posts = authors(:david).posts.merge(:includes => :comments, :order => "posts.id").to_a
    assert_equal 2, posts.first.comments.size
  end

  def test_loading_from_an_association_that_has_a_hash_of_conditions
    assert_nothing_raised do
      Author.all.merge!(:includes => :hello_posts_with_hash_conditions).to_a
    end
    assert !Author.all.merge!(:includes => :hello_posts_with_hash_conditions).find(authors(:david).id).hello_posts.empty?
  end

  def test_loading_with_no_associations
    assert_nil Post.all.merge!(:includes => :author).find(posts(:authorless).id).author
  end

  # Regression test for 21c75e5
  def test_nested_loading_does_not_raise_exception_when_association_does_not_exist
    assert_nothing_raised do
      Post.all.merge!(:includes => {:author => :author_addresss}).find(posts(:authorless).id)
    end
  end

  def test_nested_loading_through_has_one_association
    aa = AuthorAddress.all.merge!(:includes => {:author => :posts}).find(author_addresses(:david_address).id)
    assert_equal aa.author.posts.count, aa.author.posts.length
  end

  def test_nested_loading_through_has_one_association_with_order
    aa = AuthorAddress.all.merge!(:includes => {:author => :posts}, :order => 'author_addresses.id').find(author_addresses(:david_address).id)
    assert_equal aa.author.posts.count, aa.author.posts.length
  end

  def test_nested_loading_through_has_one_association_with_order_on_association
    aa = AuthorAddress.all.merge!(:includes => {:author => :posts}, :order => 'authors.id').find(author_addresses(:david_address).id)
    assert_equal aa.author.posts.count, aa.author.posts.length
  end

  def test_nested_loading_through_has_one_association_with_order_on_nested_association
    aa = AuthorAddress.all.merge!(:includes => {:author => :posts}, :order => 'posts.id').find(author_addresses(:david_address).id)
    assert_equal aa.author.posts.count, aa.author.posts.length
  end

  def test_nested_loading_through_has_one_association_with_conditions
    aa = AuthorAddress.references(:author_addresses).merge(
      :includes => {:author => :posts},
      :where => "author_addresses.id > 0"
    ).find author_addresses(:david_address).id
    assert_equal aa.author.posts.count, aa.author.posts.length
  end

  def test_nested_loading_through_has_one_association_with_conditions_on_association
    aa = AuthorAddress.references(:authors).merge(
      :includes => {:author => :posts},
      :where => "authors.id > 0"
    ).find author_addresses(:david_address).id
    assert_equal aa.author.posts.count, aa.author.posts.length
  end

  def test_nested_loading_through_has_one_association_with_conditions_on_nested_association
    aa = AuthorAddress.references(:posts).merge(
      :includes => {:author => :posts},
      :where => "posts.id > 0"
    ).find author_addresses(:david_address).id
    assert_equal aa.author.posts.count, aa.author.posts.length
  end

  def test_eager_association_loading_with_belongs_to_and_foreign_keys
    pets = Pet.all.merge!(:includes => :owner).to_a
    assert_equal 4, pets.length
  end

  def test_eager_association_loading_with_belongs_to
    comments = Comment.all.merge!(:includes => :post).to_a
    assert_equal 11, comments.length
    titles = comments.map { |c| c.post.title }
    assert titles.include?(posts(:welcome).title)
    assert titles.include?(posts(:sti_post_and_comments).title)
  end

  def test_eager_association_loading_with_belongs_to_and_limit
    comments = Comment.all.merge!(:includes => :post, :limit => 5, :order => 'comments.id').to_a
    assert_equal 5, comments.length
    assert_equal [1,2,3,5,6], comments.collect { |c| c.id }
  end

  def test_eager_association_loading_with_belongs_to_and_limit_and_conditions
    comments = Comment.all.merge!(:includes => :post, :where => 'post_id = 4', :limit => 3, :order => 'comments.id').to_a
    assert_equal 3, comments.length
    assert_equal [5,6,7], comments.collect { |c| c.id }
  end

  def test_eager_association_loading_with_belongs_to_and_limit_and_offset
    comments = Comment.all.merge!(:includes => :post, :limit => 3, :offset => 2, :order => 'comments.id').to_a
    assert_equal 3, comments.length
    assert_equal [3,5,6], comments.collect { |c| c.id }
  end

  def test_eager_association_loading_with_belongs_to_and_limit_and_offset_and_conditions
    comments = Comment.all.merge!(:includes => :post, :where => 'post_id = 4', :limit => 3, :offset => 1, :order => 'comments.id').to_a
    assert_equal 3, comments.length
    assert_equal [6,7,8], comments.collect { |c| c.id }
  end

  def test_eager_association_loading_with_belongs_to_and_limit_and_offset_and_conditions_array
    comments = Comment.all.merge!(:includes => :post, :where => ['post_id = ?',4], :limit => 3, :offset => 1, :order => 'comments.id').to_a
    assert_equal 3, comments.length
    assert_equal [6,7,8], comments.collect { |c| c.id }
  end

  def test_eager_association_loading_with_belongs_to_and_conditions_string_with_unquoted_table_name
    assert_nothing_raised do
      Comment.includes(:post).references(:posts).where('posts.id = ?', 4)
    end
  end

  def test_eager_association_loading_with_belongs_to_and_conditions_hash
    comments = []
    assert_nothing_raised do
      comments = Comment.all.merge!(:includes => :post, :where => {:posts => {:id => 4}}, :limit => 3, :order => 'comments.id').to_a
    end
    assert_equal 3, comments.length
    assert_equal [5,6,7], comments.collect { |c| c.id }
    assert_no_queries do
      comments.first.post
    end
  end

  def test_eager_association_loading_with_belongs_to_and_conditions_string_with_quoted_table_name
    quoted_posts_id= Comment.connection.quote_table_name('posts') + '.' + Comment.connection.quote_column_name('id')
    assert_nothing_raised do
      Comment.includes(:post).references(:posts).where("#{quoted_posts_id} = ?", 4)
    end
  end

  def test_eager_association_loading_with_belongs_to_and_order_string_with_unquoted_table_name
    assert_nothing_raised do
      Comment.all.merge!(:includes => :post, :order => 'posts.id').to_a
    end
  end

  def test_eager_association_loading_with_belongs_to_and_order_string_with_quoted_table_name
    quoted_posts_id= Comment.connection.quote_table_name('posts') + '.' + Comment.connection.quote_column_name('id')
    assert_nothing_raised do
      Comment.includes(:post).references(:posts).order(quoted_posts_id)
    end
  end

  def test_eager_association_loading_with_belongs_to_and_limit_and_multiple_associations
    posts = Post.all.merge!(:includes => [:author, :very_special_comment], :limit => 1, :order => 'posts.id').to_a
    assert_equal 1, posts.length
    assert_equal [1], posts.collect { |p| p.id }
  end

  def test_eager_association_loading_with_belongs_to_and_limit_and_offset_and_multiple_associations
    posts = Post.all.merge!(:includes => [:author, :very_special_comment], :limit => 1, :offset => 1, :order => 'posts.id').to_a
    assert_equal 1, posts.length
    assert_equal [2], posts.collect { |p| p.id }
  end

  def test_eager_association_loading_with_belongs_to_inferred_foreign_key_from_association_name
    author_favorite = AuthorFavorite.all.merge!(:includes => :favorite_author).first
    assert_equal authors(:mary), assert_no_queries { author_favorite.favorite_author }
  end

  def test_eager_load_belongs_to_quotes_table_and_column_names
    job = Job.includes(:ideal_reference).find jobs(:unicyclist).id
    references(:michael_unicyclist)
    assert_no_queries{ assert_equal references(:michael_unicyclist), job.ideal_reference}
  end

  def test_eager_load_has_one_quotes_table_and_column_names
    michael = Person.all.merge!(:includes => :favourite_reference).find(people(:michael))
    references(:michael_unicyclist)
    assert_no_queries{ assert_equal references(:michael_unicyclist), michael.favourite_reference}
  end

  def test_eager_load_has_many_quotes_table_and_column_names
    michael = Person.all.merge!(:includes => :references).find(people(:michael))
    references(:michael_magician,:michael_unicyclist)
    assert_no_queries{ assert_equal references(:michael_magician,:michael_unicyclist), michael.references.sort_by(&:id) }
  end

  def test_eager_load_has_many_through_quotes_table_and_column_names
    michael = Person.all.merge!(:includes => :jobs).find(people(:michael))
    jobs(:magician, :unicyclist)
    assert_no_queries{ assert_equal jobs(:unicyclist, :magician), michael.jobs.sort_by(&:id) }
  end

  def test_eager_load_has_many_with_string_keys
    subscriptions = subscriptions(:webster_awdr, :webster_rfr)
    subscriber =Subscriber.all.merge!(:includes => :subscriptions).find(subscribers(:second).id)
    assert_equal subscriptions, subscriber.subscriptions.sort_by(&:id)
  end

  def test_string_id_column_joins
    s = Subscriber.create! do |c|
      c.id = "PL"
    end

    b = Book.create!

    Subscription.create!(:subscriber_id => "PL", :book_id => b.id)
    s.reload
    s.book_ids = s.book_ids
  end

  def test_eager_load_has_many_through_with_string_keys
    books = books(:awdr, :rfr)
    subscriber = Subscriber.all.merge!(:includes => :books).find(subscribers(:second).id)
    assert_equal books, subscriber.books.sort_by(&:id)
  end

  def test_eager_load_belongs_to_with_string_keys
    subscriber = subscribers(:second)
    subscription = Subscription.all.merge!(:includes => :subscriber).find(subscriptions(:webster_awdr).id)
    assert_equal subscriber, subscription.subscriber
  end

  def test_eager_association_loading_with_explicit_join
    posts = Post.all.merge!(:includes => :comments, :joins => "INNER JOIN authors ON posts.author_id = authors.id AND authors.name = 'Mary'", :limit => 1, :order => 'author_id').to_a
    assert_equal 1, posts.length
  end

  def test_eager_with_has_many_through
    posts_with_comments = people(:michael).posts.merge(:includes => :comments, :order => 'posts.id').to_a
    posts_with_author = people(:michael).posts.merge(:includes => :author, :order => 'posts.id').to_a
    posts_with_comments_and_author = people(:michael).posts.merge(:includes => [ :comments, :author ], :order => 'posts.id').to_a
    assert_equal 2, posts_with_comments.inject(0) { |sum, post| sum + post.comments.size }
    assert_equal authors(:david), assert_no_queries { posts_with_author.first.author }
    assert_equal authors(:david), assert_no_queries { posts_with_comments_and_author.first.author }
  end

  def test_eager_with_has_many_through_a_belongs_to_association
    author = authors(:mary)
    Post.create!(:author => author, :title => "TITLE", :body => "BODY")
    author.author_favorites.create(:favorite_author_id => 1)
    author.author_favorites.create(:favorite_author_id => 2)
    posts_with_author_favorites = author.posts.merge(:includes => :author_favorites).to_a
    assert_no_queries { posts_with_author_favorites.first.author_favorites.first.author_id }
  end

  def test_eager_with_has_many_through_an_sti_join_model
    author = Author.all.merge!(:includes => :special_post_comments, :order => 'authors.id').first
    assert_equal [comments(:does_it_hurt)], assert_no_queries { author.special_post_comments }
  end

  def test_eager_with_has_many_through_an_sti_join_model_with_conditions_on_both
    author = Author.all.merge!(:includes => :special_nonexistant_post_comments, :order => 'authors.id').first
    assert_equal [], author.special_nonexistant_post_comments
  end

  def test_eager_with_has_many_through_join_model_with_conditions
    assert_equal Author.all.merge!(:includes => :hello_post_comments,
                             :order => 'authors.id').first.hello_post_comments.sort_by(&:id),
                 Author.all.merge!(:order => 'authors.id').first.hello_post_comments.sort_by(&:id)
  end

  def test_eager_with_has_many_through_join_model_with_conditions_on_top_level
    assert_equal comments(:more_greetings), Author.all.merge!(:includes => :comments_with_order_and_conditions).find(authors(:david).id).comments_with_order_and_conditions.first
  end

  def test_eager_with_has_many_through_join_model_with_include
    author_comments = Author.all.merge!(:includes => :comments_with_include).find(authors(:david).id).comments_with_include.to_a
    assert_no_queries do
      author_comments.first.post.title
    end
  end

  def test_eager_with_has_many_through_with_conditions_join_model_with_include
    post_tags = Post.find(posts(:welcome).id).misc_tags
    eager_post_tags = Post.all.merge!(:includes => :misc_tags).find(1).misc_tags
    assert_equal post_tags, eager_post_tags
  end

  def test_eager_with_has_many_through_join_model_ignores_default_includes
    assert_nothing_raised do
      authors(:david).comments_on_posts_with_default_include.to_a
    end
  end

  def test_eager_with_has_many_and_limit
    posts = Post.all.merge!(:order => 'posts.id asc', :includes => [ :author, :comments ], :limit => 2).to_a
    assert_equal 2, posts.size
    assert_equal 3, posts.inject(0) { |sum, post| sum + post.comments.size }
  end

  def test_eager_with_has_many_and_limit_and_conditions
    if current_adapter?(:OpenBaseAdapter)
      posts = Post.all.merge!(:includes => [ :author, :comments ], :limit => 2, :where => "FETCHBLOB(posts.body) = 'hello'", :order => "posts.id").to_a
    else
      posts = Post.all.merge!(:includes => [ :author, :comments ], :limit => 2, :where => "posts.body = 'hello'", :order => "posts.id").to_a
    end
    assert_equal 2, posts.size
    assert_equal [4,5], posts.collect { |p| p.id }
  end

  def test_eager_with_has_many_and_limit_and_conditions_array
    if current_adapter?(:OpenBaseAdapter)
      posts = Post.all.merge!(:includes => [ :author, :comments ], :limit => 2, :where => [ "FETCHBLOB(posts.body) = ?", 'hello' ], :order => "posts.id").to_a
    else
      posts = Post.all.merge!(:includes => [ :author, :comments ], :limit => 2, :where => [ "posts.body = ?", 'hello' ], :order => "posts.id").to_a
    end
    assert_equal 2, posts.size
    assert_equal [4,5], posts.collect { |p| p.id }
  end

  def test_eager_with_has_many_and_limit_and_conditions_array_on_the_eagers
    posts = Post.includes(:author, :comments).limit(2).references(:author).where("authors.name = ?", 'David')
    assert_equal 2, posts.size

    count = Post.includes(:author, :comments).limit(2).references(:author).where("authors.name = ?", 'David').count
    assert_equal posts.size, count
  end

  def test_eager_with_has_many_and_limit_and_high_offset
    posts = Post.all.merge!(:includes => [ :author, :comments ], :limit => 2, :offset => 10, :where => { 'authors.name' => 'David' }).to_a
    assert_equal 0, posts.size
  end

  def test_eager_with_has_many_and_limit_and_high_offset_and_multiple_array_conditions
    assert_queries(1) do
      posts = Post.references(:authors, :comments).
        merge(:includes => [ :author, :comments ], :limit => 2, :offset => 10,
          :where => [ "authors.name = ? and comments.body = ?", 'David', 'go crazy' ]).to_a
      assert_equal 0, posts.size
    end
  end

  def test_eager_with_has_many_and_limit_and_high_offset_and_multiple_hash_conditions
    assert_queries(1) do
      posts = Post.all.merge!(:includes => [ :author, :comments ], :limit => 2, :offset => 10,
        :where => { 'authors.name' => 'David', 'comments.body' => 'go crazy' }).to_a
      assert_equal 0, posts.size
    end
  end

  def test_count_eager_with_has_many_and_limit_and_high_offset
    posts = Post.all.merge!(:includes => [ :author, :comments ], :limit => 2, :offset => 10, :where => { 'authors.name' => 'David' }).count(:all)
    assert_equal 0, posts
  end

  def test_eager_with_has_many_and_limit_with_no_results
    posts = Post.all.merge!(:includes => [ :author, :comments ], :limit => 2, :where => "posts.title = 'magic forest'").to_a
    assert_equal 0, posts.size
  end

  def test_eager_count_performed_on_a_has_many_association_with_multi_table_conditional
    author = authors(:david)
    author_posts_without_comments = author.posts.select { |post| post.comments.blank? }
    assert_equal author_posts_without_comments.size, author.posts.includes(:comments).where('comments.id is null').references(:comments).count
  end

  def test_eager_count_performed_on_a_has_many_through_association_with_multi_table_conditional
    person = people(:michael)
    person_posts_without_comments = person.posts.select { |post| post.comments.blank? }
    assert_equal person_posts_without_comments.size, person.posts_with_no_comments.count
  end

  def test_eager_with_has_and_belongs_to_many_and_limit
    posts = Post.all.merge!(:includes => :categories, :order => "posts.id", :limit => 3).to_a
    assert_equal 3, posts.size
    assert_equal 2, posts[0].categories.size
    assert_equal 1, posts[1].categories.size
    assert_equal 0, posts[2].categories.size
    assert posts[0].categories.include?(categories(:technology))
    assert posts[1].categories.include?(categories(:general))
  end

  # Since the preloader for habtm gets raw row hashes from the database and then
  # instantiates them, this test ensures that it only instantiates one actual
  # object per record from the database.
  def test_has_and_belongs_to_many_should_not_instantiate_same_records_multiple_times
    welcome    = posts(:welcome)
    categories = Category.includes(:posts)

    general    = categories.find { |c| c == categories(:general) }
    technology = categories.find { |c| c == categories(:technology) }

    post1 = general.posts.to_a.find { |p| p == welcome }
    post2 = technology.posts.to_a.find { |p| p == welcome }

    assert_equal post1.object_id, post2.object_id
  end

  def test_eager_with_has_many_and_limit_and_conditions_on_the_eagers
    posts =
      authors(:david).posts
        .includes(:comments)
        .where("comments.body like 'Normal%' OR comments.#{QUOTED_TYPE}= 'SpecialComment'")
        .references(:comments)
        .limit(2)
        .to_a
    assert_equal 2, posts.size

    count =
      Post.includes(:comments, :author)
        .where("authors.name = 'David' AND (comments.body like 'Normal%' OR comments.#{QUOTED_TYPE}= 'SpecialComment')")
        .references(:authors, :comments)
        .limit(2)
        .count
    assert_equal count, posts.size
  end

  def test_eager_with_has_many_and_limit_and_scoped_conditions_on_the_eagers
    posts = nil
    Post.includes(:comments)
      .where("comments.body like 'Normal%' OR comments.#{QUOTED_TYPE}= 'SpecialComment'")
      .references(:comments)
      .scoping do

      posts = authors(:david).posts.limit(2).to_a
      assert_equal 2, posts.size
    end

    Post.includes(:comments, :author)
      .where("authors.name = 'David' AND (comments.body like 'Normal%' OR comments.#{QUOTED_TYPE}= 'SpecialComment')")
      .references(:authors, :comments)
      .scoping do

      count = Post.limit(2).count
      assert_equal count, posts.size
    end
  end

  def test_eager_association_loading_with_habtm
    posts = Post.all.merge!(:includes => :categories, :order => "posts.id").to_a
    assert_equal 2, posts[0].categories.size
    assert_equal 1, posts[1].categories.size
    assert_equal 0, posts[2].categories.size
    assert posts[0].categories.include?(categories(:technology))
    assert posts[1].categories.include?(categories(:general))
  end

  def test_eager_with_inheritance
    SpecialPost.all.merge!(:includes => [ :comments ]).to_a
  end

  def test_eager_has_one_with_association_inheritance
    post = Post.all.merge!(:includes => [ :very_special_comment ]).find(4)
    assert_equal "VerySpecialComment", post.very_special_comment.class.to_s
  end

  def test_eager_has_many_with_association_inheritance
    post = Post.all.merge!(:includes => [ :special_comments ]).find(4)
    post.special_comments.each do |special_comment|
      assert special_comment.is_a?(SpecialComment)
    end
  end

  def test_eager_habtm_with_association_inheritance
    post = Post.all.merge!(:includes => [ :special_categories ]).find(6)
    assert_equal 1, post.special_categories.size
    post.special_categories.each do |special_category|
      assert_equal "SpecialCategory", special_category.class.to_s
    end
  end

  def test_eager_with_has_one_dependent_does_not_destroy_dependent
    assert_not_nil companies(:first_firm).account
    f = Firm.all.merge!(:includes => :account,
            :where => ["companies.name = ?", "37signals"]).first
    assert_not_nil f.account
    assert_equal companies(:first_firm, :reload).account, f.account
  end

  def test_eager_with_multi_table_conditional_properly_counts_the_records_when_using_size
    author = authors(:david)
    posts_with_no_comments = author.posts.select { |post| post.comments.blank? }
    assert_equal posts_with_no_comments.size, author.posts_with_no_comments.size
    assert_equal posts_with_no_comments, author.posts_with_no_comments
  end

  def test_eager_with_invalid_association_reference
    assert_raise(ActiveRecord::AssociationNotFoundError, "Association was not found; perhaps you misspelled it?  You specified :include => :monkeys") {
      Post.all.merge!(:includes=> :monkeys ).find(6)
    }
    assert_raise(ActiveRecord::AssociationNotFoundError, "Association was not found; perhaps you misspelled it?  You specified :include => :monkeys") {
      Post.all.merge!(:includes=>[ :monkeys ]).find(6)
    }
    assert_raise(ActiveRecord::AssociationNotFoundError, "Association was not found; perhaps you misspelled it?  You specified :include => :monkeys") {
      Post.all.merge!(:includes=>[ 'monkeys' ]).find(6)
    }
    assert_raise(ActiveRecord::AssociationNotFoundError, "Association was not found; perhaps you misspelled it?  You specified :include => :monkeys, :elephants") {
      Post.all.merge!(:includes=>[ :monkeys, :elephants ]).find(6)
    }
  end

  def test_eager_with_default_scope
    developer = EagerDeveloperWithDefaultScope.where(:name => 'David').first
    projects = Project.order(:id).to_a
    assert_no_queries do
      assert_equal(projects, developer.projects)
    end
  end

  def test_eager_with_default_scope_as_class_method
    developer = EagerDeveloperWithClassMethodDefaultScope.where(:name => 'David').first
    projects = Project.order(:id).to_a
    assert_no_queries do
      assert_equal(projects, developer.projects)
    end
  end

  def test_eager_with_default_scope_as_lambda
    developer = EagerDeveloperWithLambdaDefaultScope.where(:name => 'David').first
    projects = Project.order(:id).to_a
    assert_no_queries do
      assert_equal(projects, developer.projects)
    end
  end

  def test_eager_with_default_scope_as_block
    # warm up the habtm cache
    EagerDeveloperWithBlockDefaultScope.where(:name => 'David').first.projects
    developer = EagerDeveloperWithBlockDefaultScope.where(:name => 'David').first
    projects = Project.order(:id).to_a
    assert_no_queries do
      assert_equal(projects, developer.projects)
    end
  end

  def test_eager_with_default_scope_as_callable
    developer = EagerDeveloperWithCallableDefaultScope.where(:name => 'David').first
    projects = Project.order(:id).to_a
    assert_no_queries do
      assert_equal(projects, developer.projects)
    end
  end

  def find_all_ordered(className, include=nil)
    className.all.merge!(:order=>"#{className.table_name}.#{className.primary_key}", :includes=>include).to_a
  end

  def test_limited_eager_with_order
    assert_equal(
      posts(:thinking, :sti_comments),
      Post.all.merge!(
        :includes => [:author, :comments], :where => { 'authors.name' => 'David' },
        :order => 'UPPER(posts.title)', :limit => 2, :offset => 1
      ).to_a
    )
    assert_equal(
      posts(:sti_post_and_comments, :sti_comments),
      Post.all.merge!(
        :includes => [:author, :comments], :where => { 'authors.name' => 'David' },
        :order => 'UPPER(posts.title) DESC', :limit => 2, :offset => 1
      ).to_a
    )
  end

  def test_limited_eager_with_multiple_order_columns
    assert_equal(
      posts(:thinking, :sti_comments),
      Post.all.merge!(
        :includes => [:author, :comments], :where => { 'authors.name' => 'David' },
        :order => ['UPPER(posts.title)', 'posts.id'], :limit => 2, :offset => 1
      ).to_a
    )
    assert_equal(
      posts(:sti_post_and_comments, :sti_comments),
      Post.all.merge!(
        :includes => [:author, :comments], :where => { 'authors.name' => 'David' },
        :order => ['UPPER(posts.title) DESC', 'posts.id'], :limit => 2, :offset => 1
      ).to_a
    )
  end

  def test_limited_eager_with_numeric_in_association
    assert_equal(
      people(:david, :susan),
      Person.references(:number1_fans_people).merge(
        :includes => [:readers, :primary_contact, :number1_fan],
        :where => "number1_fans_people.first_name like 'M%'",
        :order => 'people.id', :limit => 2, :offset => 0
      ).to_a
    )
  end

  def test_preload_with_interpolation
    post = Post.includes(:comments_with_interpolated_conditions).find(posts(:welcome).id)
    assert_equal [comments(:greetings)], post.comments_with_interpolated_conditions

    post = Post.joins(:comments_with_interpolated_conditions).find(posts(:welcome).id)
    assert_equal [comments(:greetings)], post.comments_with_interpolated_conditions
  end

  def test_polymorphic_type_condition
    post = Post.all.merge!(:includes => :taggings).find(posts(:thinking).id)
    assert post.taggings.include?(taggings(:thinking_general))
    post = SpecialPost.all.merge!(:includes => :taggings).find(posts(:thinking).id)
    assert post.taggings.include?(taggings(:thinking_general))
  end

  def test_eager_with_multiple_associations_with_same_table_has_many_and_habtm
    # Eager includes of has many and habtm associations aren't necessarily sorted in the same way
    def assert_equal_after_sort(item1, item2, item3 = nil)
      assert_equal(item1.sort{|a,b| a.id <=> b.id}, item2.sort{|a,b| a.id <=> b.id})
      assert_equal(item3.sort{|a,b| a.id <=> b.id}, item2.sort{|a,b| a.id <=> b.id}) if item3
    end
    # Test regular association, association with conditions, association with
    # STI, and association with conditions assured not to be true
    post_types = [:posts, :other_posts, :special_posts]
    # test both has_many and has_and_belongs_to_many
    [Author, Category].each do |className|
      d1 = find_all_ordered(className)
      # test including all post types at once
      d2 = find_all_ordered(className, post_types)
      d1.each_index do |i|
        assert_equal(d1[i], d2[i])
        assert_equal_after_sort(d1[i].posts, d2[i].posts)
        post_types[1..-1].each do |post_type|
          # test including post_types together
          d3 = find_all_ordered(className, [:posts, post_type])
          assert_equal(d1[i], d3[i])
          assert_equal_after_sort(d1[i].posts, d3[i].posts)
          assert_equal_after_sort(d1[i].send(post_type), d2[i].send(post_type), d3[i].send(post_type))
        end
      end
    end
  end

  def test_eager_with_multiple_associations_with_same_table_has_one
    d1 = find_all_ordered(Firm)
    d2 = find_all_ordered(Firm, :account)
    d1.each_index do |i|
      assert_equal(d1[i], d2[i])
      assert_equal(d1[i].account, d2[i].account)
    end
  end

  def test_eager_with_multiple_associations_with_same_table_belongs_to
    firm_types = [:firm, :firm_with_basic_id, :firm_with_other_name, :firm_with_condition]
    d1 = find_all_ordered(Client)
    d2 = find_all_ordered(Client, firm_types)
    d1.each_index do |i|
      assert_equal(d1[i], d2[i])
      firm_types.each { |type| assert_equal(d1[i].send(type), d2[i].send(type)) }
    end
  end
  def test_eager_with_valid_association_as_string_not_symbol
    assert_nothing_raised { Post.all.merge!(:includes => 'comments').to_a }
  end

  def test_eager_with_floating_point_numbers
    assert_queries(2) do
      # Before changes, the floating point numbers will be interpreted as table names and will cause this to run in one query
      Comment.all.merge!(:where => "123.456 = 123.456", :includes => :post).to_a
    end
  end

  def test_preconfigured_includes_with_belongs_to
    author = posts(:welcome).author_with_posts
    assert_no_queries {assert_equal 5, author.posts.size}
  end

  def test_preconfigured_includes_with_has_one
    comment = posts(:sti_comments).very_special_comment_with_post
    assert_no_queries {assert_equal posts(:sti_comments), comment.post}
  end

  def test_preconfigured_includes_with_has_many
    posts = authors(:david).posts_with_comments
    one = posts.detect { |p| p.id == 1 }
    assert_no_queries do
      assert_equal 5, posts.size
      assert_equal 2, one.comments.size
    end
  end

  def test_preconfigured_includes_with_habtm
    posts = authors(:david).posts_with_categories
    one = posts.detect { |p| p.id == 1 }
    assert_no_queries do
      assert_equal 5, posts.size
      assert_equal 2, one.categories.size
    end
  end

  def test_preconfigured_includes_with_has_many_and_habtm
    posts = authors(:david).posts_with_comments_and_categories
    one = posts.detect { |p| p.id == 1 }
    assert_no_queries do
      assert_equal 5, posts.size
      assert_equal 2, one.comments.size
      assert_equal 2, one.categories.size
    end
  end

  def test_count_with_include
    if current_adapter?(:SybaseAdapter)
      assert_equal 3, authors(:david).posts_with_comments.where("len(comments.body) > 15").references(:comments).count
    elsif current_adapter?(:OpenBaseAdapter)
      assert_equal 3, authors(:david).posts_with_comments.where("length(FETCHBLOB(comments.body)) > 15").references(:comments).count
    else
      assert_equal 3, authors(:david).posts_with_comments.where("length(comments.body) > 15").references(:comments).count
    end
  end

  def test_load_with_sti_sharing_association
    assert_queries(2) do #should not do 1 query per subclass
      Comment.includes(:post).to_a
    end
  end

  def test_conditions_on_join_table_with_include_and_limit
    assert_equal 3, Developer.all.merge!(:includes => 'projects', :where => { 'developers_projects.access_level' => 1 }, :limit => 5).to_a.size
  end

  def test_dont_create_temporary_active_record_instances
    Developer.instance_count = 0
    developers = Developer.all.merge!(:includes => 'projects', :where => { 'developers_projects.access_level' => 1 }, :limit => 5).to_a
    assert_equal developers.count, Developer.instance_count
  end

  def test_order_on_join_table_with_include_and_limit
    assert_equal 5, Developer.all.merge!(:includes => 'projects', :order => 'developers_projects.joined_on DESC', :limit => 5).to_a.size
  end

  def test_eager_loading_with_order_on_joined_table_preloads
    posts = assert_queries(2) do
      Post.all.merge!(:joins => :comments, :includes => :author, :order => 'comments.id DESC').to_a
    end
    assert_equal posts(:eager_other), posts[1]
    assert_equal authors(:mary), assert_no_queries { posts[1].author}
  end

  def test_eager_loading_with_conditions_on_joined_table_preloads
    posts = assert_queries(2) do
      Post.all.merge!(:select => 'distinct posts.*', :includes => :author, :joins => [:comments], :where => "comments.body like 'Thank you%'", :order => 'posts.id').to_a
    end
    assert_equal [posts(:welcome)], posts
    assert_equal authors(:david), assert_no_queries { posts[0].author}

    posts = assert_queries(2) do
      Post.all.merge!(:select => 'distinct posts.*', :includes => :author, :joins => [:comments], :where => "comments.body like 'Thank you%'", :order => 'posts.id').to_a
    end
    assert_equal [posts(:welcome)], posts
    assert_equal authors(:david), assert_no_queries { posts[0].author}

    posts = assert_queries(2) do
      Post.all.merge!(:includes => :author, :joins => {:taggings => :tag}, :where => "tags.name = 'General'", :order => 'posts.id').to_a
    end
    assert_equal posts(:welcome, :thinking), posts

    posts = assert_queries(2) do
      Post.all.merge!(:includes => :author, :joins => {:taggings => {:tag => :taggings}}, :where => "taggings_tags.super_tag_id=2", :order => 'posts.id').to_a
    end
    assert_equal posts(:welcome, :thinking), posts
  end

  def test_preload_has_many_with_association_condition_and_default_scope
    post = Post.create!(:title => 'Beaches', :body => "I like beaches!")
    Reader.create! :person => people(:david), :post => post
    LazyReader.create! :person => people(:susan), :post => post

    assert_equal 1, post.lazy_readers.to_a.size
    assert_equal 2, post.lazy_readers_skimmers_or_not.to_a.size

    post_with_readers = Post.includes(:lazy_readers_skimmers_or_not).find(post.id)
    assert_equal 2, post_with_readers.lazy_readers_skimmers_or_not.to_a.size
  end

  def test_eager_loading_with_conditions_on_string_joined_table_preloads
    posts = assert_queries(2) do
      Post.all.merge!(:select => 'distinct posts.*', :includes => :author, :joins => "INNER JOIN comments on comments.post_id = posts.id", :where => "comments.body like 'Thank you%'", :order => 'posts.id').to_a
    end
    assert_equal [posts(:welcome)], posts
    assert_equal authors(:david), assert_no_queries { posts[0].author}

    posts = assert_queries(2) do
      Post.all.merge!(:select => 'distinct posts.*', :includes => :author, :joins => ["INNER JOIN comments on comments.post_id = posts.id"], :where => "comments.body like 'Thank you%'", :order => 'posts.id').to_a
    end
    assert_equal [posts(:welcome)], posts
    assert_equal authors(:david), assert_no_queries { posts[0].author}
  end

  def test_eager_loading_with_select_on_joined_table_preloads
    posts = assert_queries(2) do
      Post.all.merge!(:select => 'posts.*, authors.name as author_name', :includes => :comments, :joins => :author, :order => 'posts.id').to_a
    end
    assert_equal 'David', posts[0].author_name
    assert_equal posts(:welcome).comments, assert_no_queries { posts[0].comments}
  end

  def test_eager_loading_with_conditions_on_join_model_preloads
    authors = assert_queries(2) do
      Author.all.merge!(:includes => :author_address, :joins => :comments, :where => "posts.title like 'Welcome%'").to_a
    end
    assert_equal authors(:david), authors[0]
    assert_equal author_addresses(:david_address), authors[0].author_address
  end

  def test_preload_belongs_to_uses_exclusive_scope
    people = Person.males.merge(:includes => :primary_contact).to_a
    assert_not_equal people.length, 0
    people.each do |person|
      assert_no_queries {assert_not_nil person.primary_contact}
      assert_equal Person.find(person.id).primary_contact, person.primary_contact
    end
  end

  def test_preload_has_many_uses_exclusive_scope
    people = Person.males.includes(:agents).to_a
    people.each do |person|
      assert_equal Person.find(person.id).agents, person.agents
    end
  end

  def test_preload_has_many_using_primary_key
    expected = Firm.first.clients_using_primary_key.to_a
    firm = Firm.includes(:clients_using_primary_key).first
    assert_no_queries do
      assert_equal expected, firm.clients_using_primary_key
    end
  end

  def test_include_has_many_using_primary_key
    expected = Firm.find(1).clients_using_primary_key.sort_by(&:name)
    # Oracle adapter truncates alias to 30 characters
    if current_adapter?(:OracleAdapter)
      firm = Firm.all.merge!(:includes => :clients_using_primary_key, :order => 'clients_using_primary_keys_companies'[0,30]+'.name').find(1)
    else
      firm = Firm.all.merge!(:includes => :clients_using_primary_key, :order => 'clients_using_primary_keys_companies.name').find(1)
    end
    assert_no_queries do
      assert_equal expected, firm.clients_using_primary_key
    end
  end

  def test_preload_has_one_using_primary_key
    expected = accounts(:signals37)
    firm = Firm.all.merge!(:includes => :account_using_primary_key, :order => 'companies.id').first
    assert_no_queries do
      assert_equal expected, firm.account_using_primary_key
    end
  end

  def test_include_has_one_using_primary_key
    expected = accounts(:signals37)
    firm = Firm.all.merge!(:includes => :account_using_primary_key, :order => 'accounts.id').to_a.detect {|f| f.id == 1}
    assert_no_queries do
      assert_equal expected, firm.account_using_primary_key
    end
  end

  def test_preloading_empty_belongs_to
    c = Client.create!(:name => 'Foo', :client_of => Company.maximum(:id) + 1)

    client = assert_queries(2) { Client.preload(:firm).find(c.id) }
    assert_no_queries { assert_nil client.firm }
  end

  def test_preloading_empty_belongs_to_polymorphic
    t = Tagging.create!(:taggable_type => 'Post', :taggable_id => Post.maximum(:id) + 1, :tag => tags(:general))

    tagging = assert_queries(2) { Tagging.preload(:taggable).find(t.id) }
    assert_no_queries { assert_nil tagging.taggable }
  end

  def test_preloading_through_empty_belongs_to
    c = Client.create!(:name => 'Foo', :client_of => Company.maximum(:id) + 1)

    client = assert_queries(2) { Client.preload(:accounts).find(c.id) }
    assert_no_queries { assert client.accounts.empty? }
  end

  def test_preloading_has_many_through_with_uniq
    mary = Author.includes(:unique_categorized_posts).where(:id => authors(:mary).id).first
    assert_equal 1, mary.unique_categorized_posts.length
    assert_equal 1, mary.unique_categorized_post_ids.length
  end

  def test_preloading_polymorphic_with_custom_foreign_type
    sponsor = sponsors(:moustache_club_sponsor_for_groucho)
    groucho = members(:groucho)

    sponsor = assert_queries(2) {
      Sponsor.includes(:thing).where(:id => sponsor.id).first
    }
    assert_no_queries { assert_equal groucho, sponsor.thing }
  end

  def test_joins_with_includes_should_preload_via_joins
    post = assert_queries(1) { Post.includes(:comments).joins(:comments).order('posts.id desc').to_a.first }

    assert_queries(0) do
      assert_not_equal 0, post.comments.to_a.count
    end
  end

  def test_join_eager_with_empty_order_should_generate_valid_sql
    assert_nothing_raised(ActiveRecord::StatementInvalid) do
      Post.includes(:comments).order("").where(:comments => {:body => "Thank you for the welcome"}).first
    end
  end

  def test_join_eager_with_nil_order_should_generate_valid_sql
    assert_nothing_raised(ActiveRecord::StatementInvalid) do
      Post.includes(:comments).order(nil).where(:comments => {:body => "Thank you for the welcome"}).first
    end
  end

  def test_deep_including_through_habtm
    # warm up habtm cache
    posts = Post.all.merge!(:includes => {:categories => :categorizations}, :order => "posts.id").to_a
    posts[0].categories[0].categorizations.length

    posts = Post.all.merge!(:includes => {:categories => :categorizations}, :order => "posts.id").to_a
    assert_no_queries { assert_equal 2, posts[0].categories[0].categorizations.length }
    assert_no_queries { assert_equal 1, posts[0].categories[1].categorizations.length }
    assert_no_queries { assert_equal 2, posts[1].categories[0].categorizations.length }
  end

  test "scoping with a circular preload" do
    assert_equal Comment.find(1), Comment.preload(:post => :comments).scoping { Comment.find(1) }
  end

  test "circular preload does not modify unscoped" do
    expected = FirstPost.unscoped.find(2)
    FirstPost.preload(:comments => :first_post).find(1)
    assert_equal expected, FirstPost.unscoped.find(2)
  end

  test "preload ignores the scoping" do
    assert_equal(
      Comment.find(1).post,
      Post.where('1 = 0').scoping { Comment.preload(:post).find(1).post }
    )
  end

  test "preloading does not cache has many association subset when preloaded with a through association" do
    author = Author.includes(:comments_with_order_and_conditions, :posts).first
    assert_no_queries { assert_equal 2, author.comments_with_order_and_conditions.size }
    assert_no_queries { assert_equal 5, author.posts.size, "should not cache a subset of the association" }
  end

  test "preloading a through association twice does not reset it" do
    members = Member.includes(current_membership: :club).includes(:club).to_a
    assert_no_queries {
      assert_equal 3, members.map(&:current_membership).map(&:club).size
    }
  end

  test "works in combination with order(:symbol) and reorder(:symbol)" do
    author = Author.includes(:posts).references(:posts).order(:name).find_by('posts.title IS NOT NULL')
    assert_equal authors(:bob), author

    author = Author.includes(:posts).references(:posts).reorder(:name).find_by('posts.title IS NOT NULL')
    assert_equal authors(:bob), author
  end

  test "preloading with a polymorphic association and using the existential predicate" do
    assert_equal authors(:david), authors(:david).essays.includes(:writer).first.writer

    assert_nothing_raised do
      authors(:david).essays.includes(:writer).any?
    end
  end

  test "preloading associations with string joins and order references" do
    author = assert_queries(2) {
      Author.includes(:posts).joins("LEFT JOIN posts ON posts.author_id = authors.id").order("posts.title DESC").first
    }
    assert_no_queries {
      assert_equal 5, author.posts.size
    }
  end

  test "including associations with where.not adds implicit references" do
    author = assert_queries(2) {
      Author.includes(:posts).where.not(posts: { title: 'Welcome to the weblog'} ).last
    }

    assert_no_queries {
      assert_equal 2, author.posts.size
    }
  end
end
