require 'sinatra'
require 'hpricot'
require 'open-uri'
require 'json'
require 'johnson'

HOMEPAGE = "http://comic.sky-fire.com/"

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
    comic_label = thumb.search("../../../../tr[2]").inner_text.strip
    episode_label = thumb.search("../../../../tr[3]").inner_text.strip
    thumbnail = thumb.search("../../../../tr[1]//img").attr("src")
    url = thumb.search("../../../../tr[2]//a").attr("href")
    comic_id = url.match(/\/HTML\/(.+)\//)[1] rescue nil
    {
      :comic_label => comic_label,
      :episode_label => episode_label,
      :thumbnail => thumbnail,
      :comic_id => comic_id,
      :url => "/#{comic_id}.json"
    }
  end
end

get '/' do
  "No free lunch!"
end

get '/index.json' do
  doc = Hpricot(open(HOMEPAGE).read)
  latest, anime, top = doc.search("table.gray_link1")
  
  latest_list = latest.search("td a img").each.collect do |thumb|
    list_comic_episodes_by_thumbnail(thumb)
  end
  
  top_list = top.search("td a img").each.collect do |thumb|
    list_comic_episodes_by_thumbnail(thumb)
  end
  
  {:top => top_list, :latest => latest_list}.to_json
end

# use comic id to find episode list
get "/:comic.json" do
  comic_id = params[:comic]
  home = find_comic_home(comic_id)
  doc = Hpricot(open(home).read)
  sp_list, normal_list = doc.search("ul.serialise_list")
  
  sp_list_links = sp_list.search("li a").collect() do |anchor|
    comic_url = anchor["href"]
    {
      :name => anchor.innerText, 
      :url => find_comic_list(comic_url)
    }
  end
  
  normal_list_links = normal_list.search("li a").collect() do |anchor|
    comic_url = anchor["href"]
    {
      :name => anchor.innerText, 
      :url => find_comic_list(comic_url)
    }
  end
  
  {:sp => sp_list_links, :normal => normal_list_links}.to_json
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