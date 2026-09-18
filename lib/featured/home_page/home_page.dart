import 'package:material_ui/material_ui.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Offset position = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              'https://media.idownloadblog.com/wp-content/uploads/2026/09/iPhone-18-Pro-iOS27RC-burgundy.webp',
              fit: BoxFit.cover,
            ),
          ),

          Center(
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  position += details.delta;
                });
              },
              child: Transform.translate(
                offset: position,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filterConfig: const ImageFilterConfig.blur(
                      sigmaX: 18,
                      sigmaY: 18,
                      bounded: true,
                    ),
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.30),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
