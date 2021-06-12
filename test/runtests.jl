using Givre
using Test

ENV["JULIA_DEBUG"] = "all"

ENV["DISPLAY"] = ":0"

function main()
    Givre.reset_timer!(Givre.to)
    app = Application()
    run(app)
    print(Givre.to)
end

main()

GC.gc()
