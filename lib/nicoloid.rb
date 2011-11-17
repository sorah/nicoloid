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
require 'termcolor'

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
                   歌愛ユキ
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
                         "VY1" => "VY1",
                         "歌愛ユキ" => "Kaai Yuki"}

  class << self
    def puts_progress(str)
      puts "<bold><blue> *</blue> <white>#{str}</white></bold>".termcolor
      yield
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
        FileUtils.remove_entry_secure(tmpdir)
      end
      FileUtils.mkdir(tmpdir)

      converted = []
      if File.exist?(output_dir)
        nicoloid_converted = "#{output_dir}/nicoloid_converted"

        if File.exist?(nicoloid_converted)
          converted =  open(nicoloid_converted,&:readlines).map(&:chomp)
        end
      else
        FileUtils.mkdir output_dir
      end

      nv.agent.set_proxy(config["proxy"]["host"],config["proxy"]["port"]) if config["proxy"]

      max = config["limit"] ? config["limit"].to_i : 10

      puts "<bold><blue>=&gt;</blue> <white>Loading list...</white></bold>".termcolor

      videos = []

      case config["source"]["from"]
      when nil, "ranking"
        config["source"]["category"] ||= config["source"]["category"].to_sym \
                                     ||  :vocaloid
        %w(method span category).each do |k|
          config["source"][k.to_sym] = config["source"][k].to_sym if config["source"][k]
        end

        videos = nv.ranking(config["source"]["category"], config["source"])
      when "vocaran"
        latest_vocaran = nv.mylist(9352163)[-1]
        if /(PL|ＰＬ) ?[:：] ?mylist\/(\d+)/ =~ latest_vocaran.description
          mylist_id = $2
          videos = nv.mylist(mylist_id)
          sleep 1
        else
          warn "<bold><red>=&gt;</red> <white>Failed to detect mylist</white></bold>".termcolor
        end
      else
        warn "WARNING: source name is wrong or not supported. you gave #{config["source"]["from"]} as source name."
      end

      videos[0...max].each_with_index do |v, i|
        puts "<bold><blue>=&gt;</blue> <white>#{i+1}. (#{v.id}) #{v.title}</white><bold>".termcolor
        begin
          skip_message = "<bold><green> *</green> <white>Skipped</white></bold>".termcolor
          (puts skip_message.termcolor; next) if converted.include?(v.id)
          (puts skip_message; sleep 7; next) if v.type == :swf

          videoname = "#{cache_dir}/#{v.id}.#{v.type}"
          thumbname = "#{tmpdir}/#{v.id}.jpg"
          cookie_jar = "#{tmpdir}/cookie.txt"

          video_downloaded = false
          puts_progress "Downloading video" do
            unless Dir["#{cache_dir}/#{v.id}.*"].empty?
              puts "<green> *</green> <white>Using from cache</white>".termcolor
              break
            end
            puts "<bold><red> *</red> <white>Seems economy</white></bold>".termcolor if v.economy?
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

              unless system("curl", "-#", "-o", videoname, "-b", cookie_jar, url)
                puts "<bold><red>=&gt;</red> <white>Failed...</white></bold>".termcolor
              end
            else
              puts "<bold><red> *</red> <white>if you have a curl, you can download videos with progress bar.</white></bold>".termcolor
              open(videoname,"wb") do |f|
                f.print v.get_video
              end
            end
          end
          video_downloaded = true

          filename = nil
          puts_progress "Converting to mp3" do
            #outext = `ffmpeg -i #{videoname} 2>&1`[/^ +Stream.+?: Audio: (.+?),/, 1]
            outext = nil
            basename = "#{i+1}_#{v.id}_#{v.title.gsub(/\//,"-")}.#{outext||"mp3"}"
            filename = "#{output_dir}/#{basename}"

            cmd = if outext
                    [ffmpeg, "-loglevel", "quiet", "-i", videoname, "-acodec", "copy", filename]
                  else
                    [ffmpeg, "-loglevel", "quiet", "-i", videoname, "-ab", "320k", filename]
                  end
            unless system(*cmd)
              puts "<bold><red>=&gt;</red> <white>Failed...</white></bold>".termcolor
              exit 1
            end
          end

          artists=artist_sorting=nil
          puts_progress "Detecting artists" do
            vt = v.title

            artists = v.tags.select{|tag| VOCALOIDS.include?(tag) }

            if artists.empty?
              puts "<green>=&gt;</green> <white>Detection by tags failed. try detecting from the title...</white>".termcolor
              artists = VOCALOIDS.inject([]){|r,i| vt.include?(i) ? r << i : r }
            end

            artists.map!{|i| VOCALOIDS_ALIAS.key?(i) ? VOCALOIDS_ALIAS[i] : i }
            artists.uniq!

            artist_sorting = artists.map{|i| VOCALOIDS_SORTING[i] || i}.join(', ')
            artists = artists.join(', ')

            puts
            puts "  #{artists}"
            puts "  #{artist_sorting}"
            puts
          end

          puts_progress "Exporting thumbnail" do
            unless system(ffmpeg, "-loglevel", "quiet", "-i", videoname, *%w(-f image2 -vframes 1 -ss 10 -an -deinterlace), thumbname)
              puts "<bold><red>=&gt;</red> <white>Failed...</white></bold>".termcolor
              exit 1
            end
          end

          puts_progress "Setting ID3 Tags..." do
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
          end
        rescue Exception => e
          files = [filename,tmpdir]
          files << videoname unless video_downloaded
          files.each do |f|
            FileUtils.remove_entry_secure f if File.exist?(f)
          end
          if e.class == Interrupt
            puts
            puts_progress("Interrupt."){}
            exit
          else
            raise e
          end
        else
          converted << v.id
          open(nicoloid_converted,"w") do |f|
            f.print converted.join("\n")
          end
        end

        puts_progress "Wait..." do
          5.times {print "."; sleep 1}
          puts
          puts
        end
      end

      puts_progress "Removing temporary directory" do
        FileUtils.remove_entry_secure tmpdir
      end
    end
  end
end

