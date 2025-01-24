struct ECSLayoutStorage{C,G,PC,GC} <: LayoutStorage{EntityID,C,C,G}
  ecs::ECSDatabase
end

Layout.get_position(storage::ECSLayoutStorage{<:Any,<:Any,PC}, object::EntityID) where {PC} = storage.ecs[object, LOCATION_COMPONENT_ID, PC]
Layout.set_position!(storage::ECSLayoutStorage{C,<:Any,PC}, object::EntityID, position::C) where {C, PC} = storage.ecs[object, LOCATION_COMPONENT_ID, PC] = position
Layout.get_geometry(storage::ECSLayoutStorage{<:Any,GC,<:Any,GC}, object::EntityID) where {GC} = storage.ecs[object, GEOMETRY_COMPONENT_ID, GC]
Layout.get_geometry(storage::ECSLayoutStorage{<:Any,Box2,<:Any,GeometryComponent}, object::EntityID) = storage.ecs[object, GEOMETRY_COMPONENT_ID, GeometryComponent].aabb
Layout.set_geometry!(storage::ECSLayoutStorage{<:Any,GC}, object::EntityID, geometry::GC) where {GC} = storage.ecs[object, GEOMETRY_COMPONENT_ID, GC] = geometry
Layout.set_geometry!(storage::ECSLayoutStorage{<:Any,Box2,<:Any,GeometryComponent}, object::EntityID, geometry::Box2) = storage.ecs[object, GEOMETRY_COMPONENT_ID, GeometryComponent] = resize_geometry(storage.ecs[object, GEOMETRY_COMPONENT_ID, GeometryComponent], geometry)
