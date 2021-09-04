using Givre
using Test
using Base.GC: gc

# ENV["JULIA_DEBUG"] = "all"

ENV["DISPLAY"] = ":0"

function main()
    Givre.reset_timer!(Givre.to)
    app = Application()
    run(app)
    print(Givre.to)
end

main()
