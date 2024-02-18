# XXX: should upstream to MetadataArrays
import DataAPI: metadata, metadatasupport, colmetadata, colmetadatasupport
metadatasupport(::Type{<:MetadataArray}) = (read=true, write=false)
metadata(ma::MetadataArray) = MetadataArrays.metadata(ma)

# XXX: should upstream to StructArrays
colmetadatasupport(::Type{<:StructArray}) = (read=true, write=false)
colmetadata(sa::StructArray, col::Symbol) = metadata(getproperty(sa, col))
colmetadata(sa::StructArray) =
    map(Tables.columns(sa)) do col
        metadatasupport(typeof(col)).read ? metadata(col) : nothing
    end
