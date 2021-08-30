#!/usr/bin/env ruby
# frozen_string_literal: true

require 'chunky_png'

module MakeWad
  # A collection of textures whos colors are mapped to a pallete
  class TextureWad
    WAD_MAGIC = 'WAD2'
    MIP_TYPE = 'D'
    PALETTE_TYPE = '@'
    NULL_BYTE = [0].pack('C')
    NULLL_SHORT = [0].pack('S')
    NULL_LONG = [0].pack('L')

    attr_reader :palette, :textures

    def initialize(palette)
      @palette = palette
      @textures = []
    end

    def add_directory(directory)
      files = Files.glob("#{directory}/**/*.png")
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
        file.write(WAD_MAGIC)
        file.write(lump_count_long)
        dir_offset_pos = file.tell
        # Placeholder until we come back to write the actual value
        file.write(NULL_LONG)

        textures.each do |texture|
          texture.offset = file.tell

          file.write(texture.name_bytes)
          file.write(texture.width_long)
          file.write(texture.height_long)

          mips_offset = file.tell
          # mipmap offset placeholders
          4.times { file.write(NULL_LONG) }

          mips = []
          4.times do
            mip = texture.scale_down(i)
            mip.offset = file.tell - texture.offset
            mip << mips
            file.write(mip.bytes)
          end

          file.scoped_seek(mips_offset) do
            mips.each do |mip|
              file.write(mip.offset_long)
            end
          end
        end

        after_last_texture = file.tell
        palette.offset = file.tell
        file.write(palette.bytes)

        dir_offset = file.tell
        file.scoped_seek(dir_offset_pos) do
          file.write([dir_offset].pack('l'))
        end

        textures.each_with_index do |texture, idx|
          next_offset = textures[idx + 1].nil? ? after_last_texture : textures[idx + 1].offset
          size = next_offset - texture.offset
          file.write(texture.offset_long)
          file.write([size].pack('l'))
          file.write([size].pack('l'))
          file.write(MIP_TYPE)
          file.write(NULL_BYTE)
          file.write(NULL_SHORT)
          file.write(texture.name_bytes)
        end

        file.write(palette.offset_long)
        file.write(palette.size_long)
        file.write(palette.size_long)
        file.write(PALETTE_TYPE)
        file.write(NULL_BYTE)
        file.write(NULL_SHORT)
        file.write("PALETTE\0\0\0\0\0\0\0\0\0")
      end
    end
  end

  # A texture of 8-bit values corresponding to the index of the TextureWad palette
  class Texture
    attr_accessor :offset
    attr_reader :width, :height, :name, :canvas

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
  end

  # A palette of 256 24-bit colors
  class Palette
    attr_accessor :offset
    attr_reader :values

    def self.from_file(filename)
      bytes = File.read(filename, 'rb')
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
      byte_str = ''
      values.each do |value|
        byte_str << [value.r, value.g, value.b].pack('C*')
      end
      byte_str
    end

    def offset_long
      [offset].pack('l')
    end

    def size_long
      [256 * 3].pack('l')
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
end

class IO
  def scoped_seek(amount, whence = IO::SEEK_SET)
    current_seek = tell
    seek(amount, whence)
    yield tell
    seek(current_seek, IO::SEEK_SET)
  end
end

def usage
  puts "Usage: #{$PROGRAM_NAME}: <in folder> <in palette> <out wad>"
end

if ARGV.length < 3
  usage
  abort
end
