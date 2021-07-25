# NoteSequences

A `NoteSequence` is an abstract representation of a musical sequence with a variety of utilities.
It can be converted to other representations of music such as the `Melody` or `Performance` representation, and can be further converted to representations useful for model training like one-hot indices.

# Installation

To install this package, do
```julia
]add https://github.com/VasanthManiVasi/NoteSequences.jl
```
or
```julia
using Pkg
Pkg.add("https://github.com/VasanthManiVasi/NoteSequences.jl")
```

# Usage

See [MusicTransformer.jl](https://github.com/VasanthManiVasi/MusicTransformer.jl) and [PerformanceRNN.jl](https://github.com/VasanthManiVasi/PerformanceRNN.jl).
