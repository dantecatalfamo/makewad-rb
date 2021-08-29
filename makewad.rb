#!/usr/bin/env ruby
# frozen_string_literal: true

require 'chunky_png'

module MakeWad
  # A collection of textures whos colors are mapped to a pallete
  class TextureWad
    WAD_MAGIC = 'WAD2'
    NULL = 0x0

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

    def to_file(filename)
      File.open(filename, 'wb') do |file|
        texture_offsets = []

        file.write(WAD_MAGIC)
        file.write([lump_count].pack('l'))
        dir_offset_pos = file.tell
        # Placeholder until we come back to write the actual value
        file.write([0].pack('l'))

        textures.each do |texture|
          texture_offsets << file.tell

          file.write(texture.name)
          file.write("\x00")

          file.write([texture.width].pack('l'))
          file.write([texture.height].pack('l'))

          mips_offset = file.tell
          # mipmap offset placeholders
          4.times { file.write([0].pack('l')) }

          mips = []
          4.times do
            mips << file.tell - texture_offsets.last
            mip = texture.scale_down(i)
            file.write(mip.pixels.pack('C*'))
          end

          file.scoped_seek(mips_offset) do
            mips.each do |offset|
              file.write([offset].pack('l'))
            end
          end
        end

        palette_offset = file.tell
        palette.values.each do |value|
          file.write([value.r].pack('C'))
          file.write([value.g].pack('C'))
          file.write([value.b].pack('C'))
        end

        dir_offset = file.tell
        file.scoped_seek(dir_offset_pos) do
          file.write([dir_offset].pack('l'))
        end

        textures.each_with_index do |texture, idx|
          offset = texture_offsets[idx]
          next_offset = texture_offsets[idx + 1]
          size = next_offset - offset
          file.write([offset].pack('l'))
          file.write([size].pack('l'))
          file.write([size].pack('l'))
          file.write('D')
          file.write([0].pack('C'))
          file.write([0].pack('S'))
          file.write(texture.name_bytes)
        end

        file.write([palette_offset].pack('l'))
        file.write([256 * 3].pack('l'))
        file.write([256 * 3].pack('l'))
        file.write('@')
        file.write([0].pack('C'))
        file.write([0].pack('S'))
        file.write("PALETTE\0\0\0\0\0\0\0\0\0")
      end
    end
  end

  # A texture of 8-bit values corresponding to the index of the TextureWad palette
  class Texture
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
