import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/home_controller.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final rc = Get.find<RemoteConfigController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Remote Config'),
        backgroundColor: rc.primaryColor.value,
      ),
      body: Center(
        child: Obx(() => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Primary Color: ${rc.primaryColor.value.value.toRadixString(16)}',
                  style: TextStyle(color: rc.primaryColor.value),
                ),
                Text(
                  'Background Color: ${rc.backgroundColor.value.value.toRadixString(16)}',
                  style: TextStyle(color: rc.backgroundColor.value),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: rc.primaryColor.value,
                  ),
                  onPressed: () async {
                    await rc.initRemoteConfig();
                  },
                  child: const Text('Refresh Colors'),
                ),
              ],
            )),
      ),
    );
  }
}
