require 'sinatra'
require 'hpricot'
require 'open-uri'
require 'json'
require 'johnson'

helpers do
  def find_comic_home(name)
    "http://comic.sky-fire.com/HTML/#{name}/"
  end
  
  def find_comic_list(url)
    matched = url.match(/^http:\/\/([^\/]+)\/AllComic\/Browser\.html\?c=([0-9]+)&v=([0-9]+)/)
    if matched
      "http://#{matched[1]}/Utility/#{matched[2]}/#{matched[3]}.js"
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
end

get '/' do
  "No free lunch!"
end

# use comic name to find comic list
get "/comic" do
  home = find_comic_home(params[:name])
  doc = Hpricot(open(home).read)
  links = doc.search("ul.serialise_list li a").collect() do |anchor|
    {
      :name => anchor.innerText, 
      :url => find_comic_list(anchor["href"])
    }
  end.to_json
end

get "/episode" do
  url = params[:url]
  find_episode_list(url).to_json
end

get "/:comic/:episode" do
  episode_id = params[:episode]
  
  link = find_comic_list_by_name(params[:comic]).select do |episode|
    suffix = "/#{episode_id}.js"
    episode[:url][-suffix.length, suffix.length] == suffix    
  end.first
  
  find_episode_list(link[:url]).to_json
end