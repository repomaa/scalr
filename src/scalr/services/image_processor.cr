require "athena"
require "pixie"

module Scalr::Services
  @[ADI::Register]
  class ImageProcessor
    struct Options
      include AVD::Validatable
      include ASR::Serializable

      enum Fit
        Cover
        Fill
        Inside
        Outside
      end

      enum Gravity
        North
        NorthWest
        West
        SouthWest
        South
        SouthEast
        East
        NorthEast
        Center
      end

      getter! width : Int32?
      getter! height : Int32?
      getter! scale : Int32
      getter gravity : Gravity = Gravity::Center
      getter fit : Fit = Fit::Inside
      getter format : String?

      def initialize(@width, @height, @scale, @format, fit : Fit?, gravity : Gravity?)
        @fit = fit unless fit.nil?
        @gravity = gravity unless gravity.nil?
      end

      @[Assert::IsTrue(message: "You must define at least one of width, height or scale")]
      def width_height_or_scale_present : Bool
        !(width? || height? || scale?).nil?
      end
    end

    def process(image : Bytes, options : Options) : Bytes
      begin
        set = Pixie::ImageSet.new(image)
      rescue ex
        Log.error { "Failed to create imageset" }
        raise ex
      end

      apply_transformations(set, options)
      options.format.try { |f| set.image_format = f }
      set.image_blob
    end

    private def apply_transformations(set : Pixie::ImageSet, options : Options) : Void
      original_width = set.image_width
      original_height = set.image_height
      aspect_ratio = original_width / original_height

      width_scale = (
        options.width? ||
        options.scale?.try { |scale| original_width * scale / 100 } ||
        options.height * aspect_ratio
      ) / original_width

      height_scale = (
        options.height? ||
        options.scale?.try { |scale| original_height * scale / 100 } ||
        options.width / aspect_ratio
      ) / original_height

      new_width = {1, (original_width * width_scale).round.to_i}.max
      new_height = {1, (original_height * height_scale).round.to_i}.max

      case options.fit
      when .cover?
        factor = {width_scale, height_scale}.max
        scale(set, factor)
        origin = origin_for(
          (original_width * factor).round.to_i,
          (original_height * factor).round.to_i,
          new_width,
          new_height,
          options.gravity
        )
        set.crop_image(new_width, new_height, *origin)
      when .fill?
        set.scale_image(new_width, new_height)
      when .inside?
        factor = {width_scale, height_scale}.min
        scale(set, factor)
      when .outside?
        factor = {width_scale, height_scale}.max
        scale(set, factor)
      end
    end

    private def scale(set : Pixie::ImageSet, factor : Float64)
      new_width = {1, (set.image_width * factor).round.to_i}.max
      new_height = {1, (set.image_height * factor).round.to_i}.max
      set.scale_image(new_width, new_height)
    end

    private def origin_for(width, height, crop_width, crop_height, gravity)
      x_west = 0
      x_center = (width - crop_width) // 2
      x_east = width - crop_width
      y_north = 0
      y_center = (height - crop_height) // 2
      y_south = height - crop_height

      case gravity
      when .north? then {x_center, y_north}
      when .north_west? then {x_west, y_north}
      when .west? then {x_west, y_center}
      when .south_west? then {x_west, y_south}
      when .south? then {x_center, y_south}
      when .south_east? then {x_east, y_south}
      when .east? then {x_east, y_center}
      when .north_east? then {x_east, y_north}
      when .center? then {x_center, y_center}
      else raise "Invalid gravity #{gravity}"
      end
    end
  end
end
