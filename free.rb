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
    matched = url.match(/^http:\/\/([^\/]+)\/AllComic\/Browser\.html\?c=([0-9]+)&v=([a-zA-Z0-9]+)/)
    if matched
      domain = matched[1]
      comic_id = matched[2]
      episode_id = matched[3]
      
      if episode_id =~ /^SP/
        "http://#{domain}/Utility/#{comic_id}/SP/#{episode_id}.js"
      else
        "http://#{domain}/Utility/#{comic_id}/#{episode_id}.js"
      end

    else
      nil
    end
  end
  
  def find_comic_list_by_name(name)
    home_url = find_comic_home(name)
    doc = Hpricot(open(home_url).read)
    links = doc.search("ul.serialise_list li a").collect() do |anchor|
      {
        :name => anchor.innerText, 
        :url => find_comic_list(anchor["href"])
      }
    end
  end
  
  def find_episode_list(episode_js)
    doc = open(episode_js).read + ";picAy"
    Johnson.evaluate(doc).to_a
  end

  def list_comic_episodes_by_thumbnail(thumb)
    name = thumb.search("../../../../tr[2]").inner_text.strip
    episode_label = thumb.search("../../../../tr[3]").inner_text.strip
    thumbnail = thumb.search("../../../../tr[1]//img").attr("src")
    url = thumb.search("../../../../tr[2]//a").attr("href")
    comic_id = url.match(/\/HTML\/(.+)\//)[1] rescue nil
    {
      :name => name,
      :comic_id => comic_id,
      :thumbnail => thumbnail,
      :episode_label => episode_label,
      :url => "/#{comic_id}.json"
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
    name = detail.search(".F14PX").inner_text.strip
    url = detail.search("a").attr("href")  
    comic_id = url.match(/\/HTML\/(.+)\//)[1] rescue nil

    {
      :name => name, 
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
get "/:comic.json" do
  comic_id = params[:comic]
  home = find_comic_home(comic_id)
  
  puts "open url: #{home}"
  doc = Hpricot(open(home).read)
  
  cover = doc.search(".comic_cover img").attr("src") rescue nil
  title = doc.search("b.F14PX").inner_text.strip rescue nil
  lists = doc.search("ul.serialise_list") || []

  if lists.size > 0
    normal_list_links = lists.pop.search("li a").collect() do |anchor|
      comic_url = anchor["href"]
      {
        :name => anchor.innerText, 
        :url => find_comic_list(comic_url)
      }
    end
  else
    normal_list_links = []
  end

  # SP is not supported
  # if lists.size > 0
  #   sp_list_links = lists.pop.search("li a").collect() do |anchor|
  #     comic_url = anchor["href"]
  #     {
  #       :name => anchor.innerText, 
  #       :url => find_comic_list(comic_url)
  #     }
  #   end
  # else
  #   sp_list_links = []
  # end
  
  {:title => title, :cover => cover,
    :sp => sp_list_links, :episodes => normal_list_links}.to_json
end


# use comic id and episode id to find pages
get "/:comic/:episode.json" do
  episode_id = params[:episode]
  comic_id = params[:comic]
  
  list = find_comic_list_by_name(comic_id)
  link = list.select do |episode|
    suffix = "/#{episode_id}.js"
    episode[:url][-suffix.length, suffix.length] == suffix    
  end.first
  
  {:comic => comic_id, :episode => episode_id, :pages => find_episode_list(link[:url])}.to_json
end
