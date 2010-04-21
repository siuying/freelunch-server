require 'sinatra'
require 'hpricot'
require 'open-uri'
require 'json'
require 'johnson'

helpers do
  def find_comic_list(url)
    matched = url.match(/^http:\/\/([^\/]+)\/AllComic\/Browser\.html\?c=([0-9]+)&v=([0-9]+)/)
    if matched
      "http://#{matched[1]}/Utility/#{matched[2]}/#{matched[3]}.js"
    else
      nil
    end
  end
  
  def find_comic_home(name)
    "http://comic.sky-fire.com/HTML/#{name}/"
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
  Johnson.evaluate("4 + 4") # => 8
  url = "http://pic2.sky-fire.com/Utility/1/305.js"
  doc = open(url).read
  doc = doc + ";picAy"
  Johnson.evaluate(doc).to_json
end