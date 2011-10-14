#-*- coding:utf-8 -*-

# nicoloid.rb
# Author: Shota Fukumori (sora_h) <sorah@tubusu.net>
# License: MIT Licence
# The MIT License {{{
#    Permission is hereby granted, free of charge, to any person obtaining a copy
#    of this software and associated documentation files (the "Software"), to deal
#    in the Software without restriction, including without limitation the rights
#    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#    copies of the Software, and to permit persons to whom the Software is
#    furnished to do so, subject to the following conditions:
#
#    The above copyright notice and this permission notice shall be included in
#    all copies or substantial portions of the Software.
#
#    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#    THE SOFTWARE.
#}}}

require 'rubygems'
require 'niconico'
require 'yaml'
require 'fileutils'
require 'taglib'

frame_factory = TagLib::ID3v2::FrameFactory.instance
frame_factory.default_text_encoding = TagLib::String::UTF8

class File
  NULL ||= /mswin/u =~ RUBY_PLATFORM ? 'NUL' : '/dev/null'
end

class Nicoloid

    VOCALOIDS = %w(初音ミク
                   鏡音リン
                   鏡音レン
                   巡音ルカ
                   KAITO
                   MEIKO
                   重音テト
                   GUMI
                   めぐっぽいど
                   Megpoid
                   がくっぽいど
                   神威がくぽ
                   がくぽ
                   VY1
                 )
    VOCALOIDS_ALIAS = {"Megpoid" => "GUMI",
                       "めぐっぽいど" => "GUMI",
                       "がくぽ" => "神威がくぽ",
                       "がくっぽいど" => "神威がくぽ",
                       "megpoid" => "GUMI"}

    VOCALOIDS_SORTING = {"初音ミク" => "Hatsune Miku",
                         "鏡音リン" => "Kagamine Rin",
                         "鏡音レン" => "Kagamine Ren",
                         "巡音ルカ" => "Megurine Ruka",
                         "KAITO" => "Kaito",
                         "MEIKO" => "Meiko",
                         "重音テト" => "Kasane Teto",
                         "GUMI" => "Gumi",
                         "神威がくぽ" => "Kamui Gakupo",
                         "VY1" => "VY1"}

  class << self
    def puts_with_result(str)
      print str
      puts yield
    end

    def run(argv)
      puts "Usage: #{File.basename(__FILE__)} [config_file=config.yml]" if argv[0] == "--help"

      config = YAML.load_file(argv[0] || "config.yml")

      nv = Niconico.new(config["account"]["mail"], config["account"]["password"])

      ffmpeg = config["ffmpeg"] || "ffmpeg"

      cache_dir = File.expand_path(config["directories"]["cache"])
      output_dir = File.expand_path(config["directories"]["output"])
      tmpdir = File.expand_path(config["directories"]["temporary"])

      if File.exist?(tmpdir)
        puts "Wiping tmp directory"
        FileUtils.remove_entry_secure(tmpdir)
      end
      FileUtils.mkdir(tmpdir)

      converted = []
      if File.exist?(output_dir)
        puts "Wiping mp3 directory"

        nicoloid_converted = "#{output_dir}/nicoloid_converted"

        if File.exist?(nicoloid_converted)
          converted =  open(nicoloid_converted,&:readlines).map(&:chomp)
        end

        #FileUtils.mv Dir.glob("#{output_dir}/*.mp3"),File.expand_path(tmpdir)
        # Dir["#{output_dir}/*.mp3"].reject do |mp3|
        #   converted.include? mp3.scan(/^#{Regexp.escape(output_dir)}\/\d+?_(.+?)_(.+?)\.mp3$/)[0][0]
        # end
      end

      nv.agent.set_proxy(config["proxy"]["host"],config["proxy"]["port"]) if config["proxy"]

      max = config["max"] ? config["max"].to_i : 10

      puts "Loading list..."
      puts

      videos = []

      case config["source"]["from"]
      when nil, "ranking"
        config["source"]["category"] ||= config["source"]["category"].to_sym \
                                     ||  :vocaloid
        %w(method span).each do |k|
          config["source"][k] = config["source"][k].to_sym if config["source"][k]
        end

        videos = nv.ranking(config["source"]["category"], config["source"])
      else
        warn "WARNING: source name is wrong or not supported. you gave #{config["source"]["from"]} as source name."
      end

      videos[0..max].each_with_index do |v, i|
        puts "#{i+1}. (#{v.id}) #{v.title}"
        begin
          (puts "  Skipped"; next) if converted.include?(v.id)
          (puts "  Skipped"; sleep 7; next) if v.type == :swf
          basename = "#{i+1}_#{v.id}_#{v.title}.mp3"
          filename = "#{output_dir}/#{basename}"
          videoname = "#{cache_dir}/#{v.id}.#{v.type}"
          thumbname = "#{tmpdir}/#{v.id}.jpg"
          cookie_jar = "#{tmpdir}/cookie.txt"

          exist_in_tmp = Dir.glob("#{tmpdir}/*_#{v.id}_*.mp3")[0]

          if exist_in_tmp
            puts "  Already converted. Skipping..."
            FileUtils.mv(exist_in_tmp, filename)
            next
          else
            puts_with_result "Saving video... " do
              break "already done!" unless Dir["#{cache_dir}/#{v.id}.*"].empty?
              if (`curl --help` rescue nil)
                a = v.get_video_by_other
                cookies = a[:cookie]
                url = a[:url]

                open(cookie_jar, "w") do |io|
                  io.puts cookies.map { |cookie|
                    [cookie.domain, "TRUE", cookie.path,
                     cookie.secure.inspect.upcase, cookie.expires.to_i,
                     cookie.name, cookie.value].join("\t")
                  }.join("\n")
                end

                puts
                system "curl", "-#", "-o", videoname, "-b", cookie_jar, url
                ""
              else
                open(videoname,"wb") do |f|
                  f.print v.get_video
                end
                "done!"
              end
            end

            puts_with_result "--------- Convert ---------" do
              puts
              unless system(ffmpeg, "-loglevel", "quiet",  "-i", videoname, "-ab", "320k",  filename)
                abort "Error..."
              end
              "---------  Done!  ---------"
            end

            artists=artist_sorting=nil
            puts_with_result "  Detecting Artists... " do
              vt = v.title

              artists = v.tags.select{|tag| VOCALOIDS.include?(tag) }

              if artists.empty?
                artists = VOCALOIDS.inject([]){|r,i| vt.include?(i) ? r << i : r }
              end

              artists.map!{|i| VOCALOIDS_ALIAS.key?(i) ? VOCALOIDS_ALIAS[i] : i }
              artists.uniq!

              artist_sorting = artists.map{|i| VOCALOIDS_SORTING[i] || i}.join(', ')
              artists = artists.join(', ')
              ["done!", "  #{artists}", "  #{artist_sorting}"].join("\n")
            end

            puts_with_result "  Exporting thumbnail... " do
              system(ffmpeg, "-ss", "10", "-vframes", "50", "-i", videoname, "-f", "image2", thumbname, :out => File::NULL, :err => File::NULL)
              "done!"
            end

            puts_with_result "  Setting ID3 Tags... " do
              file = TagLib::MPEG::File.new(filename)
              tag = file.id3v2_tag
              tag.artist = artists
              tag.title = v.title
              tag.album = v.title

              cover = TagLib::ID3v2::AttachedPictureFrame.new
              cover.mime_type = "image/jpeg"
              cover.description = "cover"
              cover.type = TagLib::ID3v2::AttachedPictureFrame::FrontCover
              cover.picture = File.open(thumbname, "rb").read

              sort = TagLib::ID3v2::TextIdentificationFrame.new("TSOP",TagLib::String::UTF8)
              sort.text = artist_sorting

              tag.add_frame(cover)
              tag.add_frame(sort)

              file.save

              "done!"
            end
          end
        rescue Exception => e
          [videoname,filename,tmpdir].each do |f|
            FileUtils.remove_entry_secure f if File.exist?(f)
          end
          raise e
        else
          converted << v.id
          open(nicoloid_converted,"w") do |f|
            f.print converted.join("\n")
          end
        end

        print "Waiting"
        5.times {print "."; sleep 1}
        puts "\n\n"
      end

      puts "Wiping tmp directory"
      FileUtils.remove_entry_secure tmpdir

      puts "Exiting...."
    end
  end
end

