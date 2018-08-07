# The TypeaheadService class is a utility class whose purpose is to provide fast responses to text queries within
# different categories (record types, functionality, subsystems, etc).
# Though similar in operation to the SearchService, the implementation is separate, in that the goal of the response
# is to provide _fast_ returns at a higher level than a general search.  In effect, TypeaheadService provides pointers to
# better searches, while SearchService provides deep and detailed information.
#
# See SrchScope class for more details about the reusable scope
# that Typeahead and Search services use
class TypeaheadService
  def initialize; end
  include SolrToggle

  def tags(input, limit = 5)
    Tag.includes(:node)
      .references(:node)
      .where('node.status = 1')
      .limit(limit)
      .where('name LIKE ?', '%' + input + '%')
      .group('node.nid')
  end

  def comments(input, limit = 5)
    if ActiveRecord::Base.connection.adapter_name == 'Mysql2'
      Comment.search(input)
        .limit(limit)
        .order('nid DESC')
        .where(status: 1)
    else 
      Comment.limit(limit)
        .order('nid DESC')
        .where('status = 1 AND comment LIKE ?', '%' + input + '%')
    end
  end

  def notes(input, limit = 5)
    if ActiveRecord::Base.connection.adapter_name == 'Mysql2'
      Node.search(input)
        .group(:nid)
        .includes(:node)
        .references(:node)
        .limit(limit)
        .where("node.type": "note", "node.status": 1)
        .order('node.changed DESC')
    else 
      Node.limit(limit)
        .group(:nid)
        .where(type: "note", status: 1)
        .order(changed: :desc)
        .where('title LIKE ?', '%' + input + '%')
    end
  end

  def wikis(input, limit = 5)
    if ActiveRecord::Base.connection.adapter_name == 'Mysql2'
      Node.search(input)
        .group('node.nid')
        .includes(:node)
        .references(:node)
        .limit(limit)
        .where("node.type": "page", "node.status": 1)
    else 
      Node.limit(limit)
        .order('nid DESC')
        .where('type = "page" AND node.status = 1 AND title LIKE ?', '%' + input + '%')
    end
  end

  def maps(input, limit = 5, order = :default)
    nodes(input, limit, order)
      .where("node.type": "map")
  end

  # Run a search in any of the associated systems for references that contain the search string

  def search_all(search_string, limit = 5)
    sresult = TagList.new
    unless search_string.nil? || search_string.blank?
      # notes
      notesrch = search_notes(search_string, limit)
      sresult.addAll(notesrch.getTags)
      # wikis
      wikisrch = search_wikis(search_string, limit)
      sresult.addAll(wikisrch.getTags)
      # User profiles
      usersrch = search_profiles(search_string, limit)
      sresult.addAll(usersrch.getTags)
      # Tags -- handled differently because tag
      tagsrch = search_tags(search_string, limit)
      sresult.addAll(tagsrch.getTags)
      # maps
      mapsrch = search_maps(search_string, limit)
      sresult.addAll(mapsrch.getTags)
      # questions
      qsrch = search_questions(search_string, limit)
      sresult.addAll(qsrch.getTags)
      # comments
      commentsrch = search_comments(search_string, limit)
      sresult.addAll(commentsrch.getTags)
    end
    sresult
  end

  def search_profiles(search_string, limit = 5)
    sresult = TagList.new
    unless search_string.nil? || search_string.blank?
      users = SrchScope.find_users(search_string, limit)
      users.each do |match|
        tval = TagResult.new
        tval.tagId = 0
        tval.tagType = 'user'
        tval.tagVal = match.username
        tval.tagSource = '/profile/' + match.username
        sresult.addTag(tval)
      end
    end
    sresult
  end

  def search_notes(search_string, limit = 5)
    sresult = TagList.new
    unless search_string.nil? || search_string.blank?
      notes(search_string, limit).uniq.each do |match|
        tval = TagResult.new
        tval.tagId = match.nid
        tval.tagVal = match.title
        tval.tagType = 'file'
        tval.tagSource = match.path
        sresult.addTag(tval)
      end
    end
    sresult
  end

  def search_wikis(search_string, limit = 5)
    sresult = TagList.new
    unless search_string.nil? || search_string.blank?
      wikis = SrchScope.find_wikis(search_string, limit, order = :default)
      wikis.select('node.title,node.type,node.nid,node.path').each do |match|
        tval = TagResult.new
        tval.tagId = match.nid
        tval.tagVal = match.title
        tval.tagType = 'file'
        tval.tagSource = match.path
        sresult.addTag(tval)
      end
    end
    sresult
  end

  def search_maps(search_string, limit = 5)
    sresult = TagList.new
    unless search_string.nil? || search_string.blank?
      # maps
      maps(search_string, limit).select('title,type,nid,path').each do |match|
        tval = TagResult.new
        tval.tagId = match.nid
        tval.tagVal = match.title
        tval.tagType = match.icon
        tval.tagSource = match.path
        sresult.addTag(tval)
      end
    end
    sresult
  end

  def search_tags(search_string, limit = 5)
    sresult = TagList.new
    unless search_string.nil? || search_string.blank?
      # Tags
      tlist = tags(search_string, limit)
      tlist.each do |match|
        ntag = TagResult.new
        ntag.tagId = 0
        ntag.tagVal = match.name
        ntag.tagType = 'tag'
        sresult.addTag(ntag)
      end
    end
    sresult
  end

  def search_questions(input, limit = 5)
    sresult = TagList.new
    questions = SrchScope.find_questions(input, limit, order = :default)
    questions.each do |match|
      tval = TagResult.fromSearch(
        match.nid,
        match.title,
        'question-circle',
        match.path
      )
      sresult.addTag(tval)
    end
    sresult
  end

  # Search comments for matching text and package up as a TagResult
  def search_comments(search_string, limit = 5)
    sresult = TagList.new
    unless search_string.nil? || search_string.blank?
      comments = SrchScope.find_comments(search_string, limit)
      comments.each do |match|
        tval = TagResult.new
        tval.tagId = match.pid
        tval.tagVal = match.comment.truncate(20)
        tval.tagType = 'comment'
        tval.tagSource = match.parent.path
        sresult.addTag(tval)
      end
    end
    sresult
  end
end
