abstract type AbstractDiff{T} end

function Base.empty!(diff::AbstractDiff)
  empty!(diff.additions)
  empty!(diff.deletions)
  diff
end

Base.length(diff::AbstractDiff) = length(diff.additions) + length(diff.deletions)
Base.isempty(diff::AbstractDiff) = length(diff) == 0

struct DiffVector{T} <: AbstractDiff{T}
  additions::Vector{T}
  deletions::Vector{T}
end
DiffVector{T}() where {T} = DiffVector{T}(T[], T[])

struct DiffSet{T} <: AbstractDiff{T}
  additions::Set{T}
  deletions::Set{T}
end
DiffSet{T}() where {T} = DiffSet{T}(Set{T}(), Set{T}())
