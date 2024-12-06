struct ECSLayoutStorage{C,G,PC,GC} <: LayoutStorage{EntityID,C,C,G}
  ecs::ECSDatabase
end

Layout.get_position(storage::ECSLayoutStorage{<:Any,<:Any,PC}, object::EntityID) where {PC} = storage.ecs[object, LOCATION_COMPONENT_ID, PC]
Layout.set_position!(storage::ECSLayoutStorage{C,<:Any,PC}, object::EntityID, position::C) where {C, PC} = storage.ecs[object, LOCATION_COMPONENT_ID, PC] = position
Layout.get_geometry(storage::ECSLayoutStorage{<:Any,GC,<:Any,GC}, object::EntityID) where {GC} = storage.ecs[object, GEOMETRY_COMPONENT_ID, GC]
Layout.set_geometry!(storage::ECSLayoutStorage{<:Any,GC}, object::EntityID, geometry::GC) where {GC} = storage.ecs[object, GEOMETRY_COMPONENT_ID, GC] = geometry
