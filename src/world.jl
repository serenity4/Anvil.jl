struct WorldTransform
  location::Point2f
  # rotation
  # scaling
end

WorldTransform() = WorldTransform(zero(Point2f))
