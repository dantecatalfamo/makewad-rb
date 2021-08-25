#!/usr/bin/env ruby
# frozen_string_literal: true

require 'chunky_png'

module MakeWad
  # A collection of textures whos colors are mapped to a pallete
  class TextureWad
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
        file.write('WAD2')
        file.write([lump_count].pack('l'))
        dir_offset_pos = file.tell
        # Placeholder until we come back to write the actual value
        file.write([0].pack('l'))

        # TODO: Finish write
      end
    end
  end

  # A texture of 8-bit values corresponding to the index of the TextureWad palette
  class Texture
    attr_reader :width, :height, :name, :data

    def initialize(width, height, name)
      @width = width
      @height = height
      @name = name
      @data = Array.new(width) { Array.new(height) }
    end

    def name=(new_name)
      if new_name.length < 15
        puts "Warning: \"#{new_name}\" will be truncated to 15 characters."
        new_name = new_name[0...15]
      end
      @name = new_name
    end

    def [](x, y)
      @data[x, y]
    end

    def []=(x, y, value)
      @data[x, y] = value
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
        distance = ChunkyPNG::Color.euclidean_distance_rgba(color, value)
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

def usage
  puts "Usage: #{$PROGRAM_NAME}: <in folder> <in palette> <out wad>"
end

if ARGV.length < 3
  usage
  abort
end
