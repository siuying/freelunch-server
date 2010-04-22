require 'sinatra'
require 'hpricot'
require 'open-uri'
require 'json'
require 'johnson'

HOME_URL = "http://comic.sky-fire.com/"
CATALOG_URL = "http://comic.sky-fire.com/Catalog/"

helpers do
  def find_comic_home(name)
    "http://comic.sky-fire.com/HTML/#{name}/"
  end
  
  def find_comic_list(url)
    matched = url.match(/^http:\/\/([^\/]+)\/AllComic\/Browser\.html\?c=([0-9]+)/)
    if matched
      domain = matched[1]
      comic_id = url.match(/c=([a-zA-Z0-9]+)/)[1] rescue nil
      episode_id = url.match(/v=([a-zA-Z0-9]+)/)[1] rescue nil
      topic_id = url.match(/t=([a-zA-Z0-9]+)/)[1] rescue nil
      
      if topic_id
        "http://#{domain}/Utility/#{comic_id}/#{topic_id}/#{episode_id}.js"
        
      else
        "http://#{domain}/Utility/#{comic_id}/#{episode_id}.js"

      end
    else
      nil
    end
  end
  
  def parse_comic_page_link(url)
    domain = url.match(/http:\/\/([^\/]+)/)[1] rescue nil
    comic_id = url.match(/c=([a-zA-Z0-9]+)/)[1] rescue nil
    episode_id = url.match(/v=([a-zA-Z0-9]+)/)[1] rescue nil
    topic_id =  url.match(/t=([a-zA-Z0-9]+)/)[1] rescue nil
    [domain, comic_id, episode_id, topic_id]
  end
  
  def generate_local_comic_page_link(domain, comic_id, episode_id, topic_id=nil)
    if topic_id
      "/pages/#{domain}/#{comic_id}/#{topic_id}/#{episode_id}.json"
    else
      "/pages/#{domain}/#{comic_id}/#{episode_id}.json"
    end
  end
  
  def convert_comic_page(fromUrl)
    domain, comic_id, episode_id, topic_id = parse_comic_page_link(fromUrl)
    generate_local_comic_page_link(domain, comic_id, episode_id, topic_id)
  end
  
  def find_episode_list(episode_js)
    doc = open(episode_js).read + ";picAy"
    Johnson.evaluate(doc).to_a
  end

  def list_comic_episodes_by_thumbnail(thumb)
    comic_title = thumb.search("../../../../tr[2]").inner_text.strip
    episode_title = thumb.search("../../../../tr[3]").inner_text.strip
    thumbnail = thumb.search("../../../../tr[1]//img").attr("src")
    url = thumb.search("../../../../tr[2]//a").attr("href")
    comic_alias = url.match(/\/HTML\/(.+)\//)[1] rescue nil
    {
      :comic_name => comic_title,
      :comic_alias => comic_alias,
      :thumbnail => thumbnail,
      :episode_name => episode_title,
      :url => "/#{comic_alias}.json"
    }
  end
  
  def parse_catalog_link(link)
    page_index = link.match(/PageIndex=([0-9]+)/)[1] rescue nil
    topic_index = link.match(/tid=([0-9]+)/)[1] rescue nil
    {:page_index => page_index, :topic_index => topic_index }
  end
  
  def generate_local_catalog_link(options={})
    page_index = options[:page_index] || "1"    # page 1
    topic_index = options[:topic_index] || "-1" # all topic
    "/catalog.json?pid=#{page_index}&tid=#{topic_index}"
  end
  
  def get_episode_pages(domain, comic_id, episode_id, topic_id=nil)
    if topic_id
      url = "http://#{domain}/Utility/#{comic_id}/#{topic_id}/#{episode_id}.js"
    else
      url = "http://#{domain}/Utility/#{comic_id}/#{episode_id}.js"
    end
    
    johnson = Johnson::Runtime.new
    js = open(url).read
    johnson.evaluate(js)

    pages = johnson["picAy"].to_a
    page_count = johnson["picCount"]
    next_volume = johnson["nextVolume"]
    pre_volume = johnson["preVolume"]
    comic_title = johnson["comicName"]

    next_volume = (next_volume =~ /javascript/) ? nil : convert_comic_page(next_volume)
    pre_volume = (pre_volume =~ /javascript/) ? nil : convert_comic_page(pre_volume)    
                
    {
      :comic_name => comic_title, :comic_id => comic_id, :episode_id => episode_id, :pages => pages, 
      :page_count => page_count, :pre_volume => pre_volume, :next_volume => next_volume
    }
  end
end

get '/' do
  "No free lunch!"
end

get '/index.json' do
  doc = Hpricot(open(HOME_URL).read)
  latest, anime, top = doc.search("table.gray_link1")
  
  latest_list = latest.search("td a img").each.collect do |thumb|
    list_comic_episodes_by_thumbnail(thumb)
  end
  
  top_list = top.search("td a img").each.collect do |thumb|
    list_comic_episodes_by_thumbnail(thumb)
  end
  
  {:top => top_list, :latest => latest_list}.to_json
end

get "/catalog.json" do
  page_index = params[:pid] || "1"
  topic_index = params[:tid] || "-1"
  
  doc = Hpricot(open(CATALOG_URL + "?PageIndex=#{page_index}&tid=#{topic_index}").read)
  data = doc.search("ul.Comic_Pic_List").collect do |comic_block|
    thumbnail, detail = comic_block.search("li")

    thumbnail_url = thumbnail.search("img").attr("src")    
    comic_title = detail.search(".F14PX").inner_text.strip
    url = detail.search("a").attr("href")  
    comic_id = url.match(/\/HTML\/(.+)\//)[1] rescue nil

    {
      :comic_name => comic_title, 
      :comic_id => comic_id, 
      :thumbnail => thumbnail_url, 
      :url => "/#{comic_id}.json"
    }
  end

  current_page = doc.search(".pagebarCurrent").inner_text.to_i rescue 1
  next_url = doc.search(".pagebarNext a").attr("href") rescue nil
  next_param = parse_catalog_link(next_url)
  next_url_local = generate_local_catalog_link(next_param)

  {:list => data, :current_page => current_page, :next_url => next_url_local}.to_json
end

get "/version.json" do
  {:major => 1, :minor => 1, :text => "1.0"}.to_json
end

# use comic id to find episode list
get "/:comic_alias.json" do
  comic_alias = params[:comic_alias]
  home = find_comic_home(comic_alias)
  
  puts "open url: #{home}"
  doc = Hpricot(open(home).read)
  
  cover = doc.search(".comic_cover img").attr("src") rescue nil
  title = doc.search("b.F14PX").inner_text.strip rescue nil
  lists = doc.search("ul.serialise_list") || []

  if lists.size > 0
    normal_list_links = lists.pop.search("li a").collect() do |anchor|
      comic_url = anchor["href"]
      episode_label = anchor.inner_text.strip

      comic_id, episode_id, topic_id = parse_comic_page_link(comic_url)
      url = generate_local_comic_page_link(comic_id, episode_id, topic_id)
      {
        :episode_name => episode_label,
        :url => url
      }
    end
  else
    normal_list_links = []
  end

  # SP is not supported
  if lists.size > 0
    sp_list_links = lists.pop.search("li a").collect() do |anchor|
      comic_url = anchor["href"]
      episode_label = anchor.inner_text.strip
      comic_id, episode_id, topic_id = parse_comic_page_link(comic_url)
      url = generate_local_comic_page_link(comic_id, episode_id, topic_id)
      {
        :episode_name => episode_label,
        :url => url
      }
    end
  else
    sp_list_links = []
  end
  
  {
   :comic_name => title, 
   :cover => cover,
   :episodes => normal_list_links,
   :sp => sp_list_links
  }.to_json
end


# use comic id and episode id to find pages
get "/pages/:domain/:comic/:episode.json" do
  domain = params[:domain]
  episode_id = params[:episode]
  comic_id = params[:comic]
  topic_id = params[:topic]

  get_episode_pages(domain, comic_id, episode_id, topic_id).to_json
end

get "/pages/:domain/:comic/:topic/:episode.json" do
  domain = params[:domain]
  episode_id = params[:episode]
  comic_id = params[:comic]
  topic_id = params[:topic]

  get_episode_pages(domain, comic_id, episode_id, topic_id).to_json
end

