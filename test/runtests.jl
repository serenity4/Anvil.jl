using Givre, Test
using FileIO
using ImageIO

instance, device = init();

rec = Rectangle(Point(0.0, 0.0), Box(Scaling(1f0, 1f0)), (0.5, 0.5, 0.9, 1.0));
data = render_object(device, rec);
save("tmp.png", data)

main()
