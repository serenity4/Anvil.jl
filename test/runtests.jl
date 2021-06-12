using Givre
using Test

ENV["JULIA_DEBUG"] = "all"

ENV["DISPLAY"] = ":0"

function main()
    app = Application()
    run(app)
end

main()

GC.gc()
