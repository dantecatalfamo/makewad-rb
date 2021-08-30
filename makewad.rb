#!/usr/bin/env ruby
# frozen_string_literal: true

require 'stringio'
require 'chunky_png'

module MakeWad
  WAD_MAGIC = 'WAD2'
  MIP_TYPE = 'D'
  PALETTE_TYPE = '@'
  NULL_BYTE = [0].pack('C')
  NULLL_SHORT = [0].pack('S')
  NULL_LONG = [0].pack('L')

  # A collection of textures whos colors are mapped to a pallete
  class TextureWad
    attr_reader :palette, :textures

    def initialize(palette)
      @palette = palette
      @textures = []
    end

    def add_directory(directory)
      files = Dir.glob("#{directory}/**/*.png")
      files.each { |file| add_file(file) }
    end

    def add_file(file)
      png = ChunkyPNG::Image.from_file(file)
      name = File.basename(file, '.png')
      texture = Texture.new(png.width, png.height, name)
      png.width.times do |x|
        png.height.times do |y|
          texture[x, y] = palette.nearest_entry(png[x, y])
        end
      end
      @textures << texture
    end

    def lump_count
      @textures.length + 1
    end

    def lump_count_long
      [lump_count].pack('l')
    end

    def to_file(filename)
      File.open(filename, 'wb') do |file|
        file << WAD_MAGIC
        file << lump_count_long
        dir_offset_pos = file.tell
        # Placeholder until we come back to write the actual value
        file << NULL_LONG

        textures.each do |texture|
          texture.offset = file.tell
          file << texture.mipmap
        end

        palette.offset = file.tell
        file << palette.bytes

        dir_offset = file.tell

        textures.each do |texture|
          file << texture.directory_entry
        end

        file << palette.directory_entry

        file.seek(dir_offset_pos)
        file << [dir_offset].pack('l')
      end
    end
  end

  # A texture of 8-bit values corresponding to the index of the TextureWad palette
  class Texture
    attr_accessor :offset
    attr_reader :width, :height, :name, :canvas, :mipmap_size

    def initialize(width, height, name, initial = nil)
      @width = width
      @height = height
      self.name = name
      @canvas = initial || ChunkyPNG::Canvas.new(width, height)
    end

    def name=(new_name)
      if new_name.length < 15
        puts "Warning: \"#{new_name}\" will be truncated to 15 characters."
        new_name = new_name[0...15]
      end
      @name = new_name
    end

    def name_bytes
      bytes = Array.new(16, "\x00")
      name.chars.each_with_index do |char, idx|
        bytes[idx] = char
      end
      bytes.join
    end

    def bytes
      canvas.pixels.pack('C*')
    end

    def width_long
      [width].pack('l')
    end

    def height_long
      [height].pack('l')
    end

    def offset_long
      [offset].pack('l')
    end

    def [](x, y)
      canvas[x, y]
    end

    def []=(x, y, value)
      canvas[x, y] = value
    end

    def scale_down(factor)
      new_width = width / (2 * factor)
      new_height = height / (2 * factor)
      scaled = canvas.resample_nearest_neighbor(new_width, new_height)
      Texture.new(new_width, new_height, name, scaled)
    end

    def mipmap
      buf = StringIO.new
      buf << texture.name_bytes
      buf << texture.width_long
      buf << texture.height_long

      mips_offset = buf.tell
      # mipmap offset placeholders
      buf << NULL_LONG * 4

      mips = []
      4.times do |i|
        mip = scale_down(i)
        mip.offset = buf.tell
        mip << mips
        buf << mip.bytes
      end

      buf.seek(mips_offset)
      mips.each do |mip|
        buf << mip.offset_long
      end
      @mipmap_size = buf.size
      buf.string
    end

    def mipmap_size_long
      [mipmap_size].pack('l')
    end

    def directory_entry
      buf = StringIO.new
      buf << offset_long
      buf << mipmap_size_long
      buf << mipmap_size_long
      buf << MIP_TYPE
      buf << NULL_BYTE
      buf << NULL_SHORT
      buf << name_bytes
      buf.string
    end
  end

  # A palette of 256 24-bit colors
  class Palette
    attr_accessor :offset
    attr_reader :values

    def self.from_file(filename)
      bytes = File.read(filename).bytes
      values = []
      256.times do
        values << PaletteColor.new(*bytes.shift(3))
      end
      new(values)
    end

    def initialize(values)
      @values = values
    end

    def nearest_entry(color)
      return 0 if ChunkyPNG::Color.a(color).zero?

      best_match = 0
      best_distance = Float::INFINITY
      values.each_with_index do |value, idx|
        distance = ChunkyPNG::Color.euclidean_distance_rgba(color, value.to_i)
        if distance < best_distance
          best_distance = distance
          best_match = idx
        end
      end
      best_match
    end

    def bytes
      buf = StringIO.new
      values.each do |value|
        buf << [value.r, value.g, value.b].pack('C*')
      end
      buf.string
    end

    def offset_long
      [offset].pack('l')
    end

    def size_long
      [256 * 3].pack('l')
    end

    def directory_entry
      buf = StringIO.new
      buf << offset_long
      buf << size_long
      buf << size_long
      buf << PALETTE_TYPE
      buf << NULL_BYTE
      buf << NULL_SHORT
      buf << "PALETTE\0\0\0\0\0\0\0\0\0"
      buf.string
    end

    # RGB representation of a pixel
    class PaletteColor
      attr_reader :r, :g, :b, :to_i

      def initialize(red, green, blue)
        @r = red
        @g = green
        @b = blue
        @to_i = ChunkyPNG::Color(r, g, b)
      end
    end
  end

  class CLI
    def usage
      puts "Usage: #{$PROGRAM_NAME}: <in folder> <in palette> <out wad>"
    end

    def run
      if ARGV.length != 3
        usage
        abort
      end
      texture_directory = ARGV[0]
      palette_file = ARGV[1]
      wad_filename = ARGV[2]
      abort %(Palette file "#{palette_file}" does not exist) unless File.exist?(palette_file)
      abort %(Texture directory "#{texture_directory}" does not exist) unless Dir.exist?(texture_directory)
      palette = Palette.from_file(palette_file)
      wad = TextureWad.new(palette)
      wad.add_directory(texture_directory)
      wad.to_file(wad_filename)
      puts %(Texture WAD exported to "#{wad_filename} successfully")
    end
  end
end

MakeWad::CLI.new.run
