import 'package:flutter/material.dart';
import 'package:flutter_remote_config/firebase_options.dart';
import 'package:flutter_remote_config/views/home_page.dart';
import 'package:get/get.dart';
import 'controllers/home_controller.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
    Get.put(RemoteConfigController()); 
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
      final rc = Get.find<RemoteConfigController>();

    return Obx(() => GetMaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Remote Config Demo',
          theme: ThemeData(
            primaryColor: rc.primaryColor.value,
            scaffoldBackgroundColor: rc.backgroundColor.value,
          ),
          home:  HomePage(),
        ));
  
  }
}
