import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SkyBoostApp());
}

// ============================================
// MODÈLES DE DONNÉES
// ============================================

class User {
  final int id;
  final String username;
  final String email;
  final double balance;
  final String currency;
  final String? referralCode;
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.balance,
    this.currency = 'XOF',
    this.referralCode,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      balance: (json['solde'] ?? 0.0).toDouble(),
      currency: json['devise'] ?? 'XOF',
      referralCode: json['referral_code'],
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toString()),
    );
  }
}

class Service {
  final String id;
  final String name;
  final String category;
  final double rate;
  final int min;
  final int max;
  final String type;

  Service({
    required this.id,
    required this.name,
    required this.category,
    required this.rate,
    required this.min,
    required this.max,
    required this.type,
  });

  factory Service.fromJson(Map<String, dynamic> json) {
    return Service(
      id: json['id'] ?? json['service'] ?? '',
      name: json['name'] ?? '',
      category: json['category'] ?? '',
      rate: double.tryParse(json['rate'].toString()) ?? 0.0,
      min: int.tryParse(json['min'].toString()) ?? 0,
      max: int.tryParse(json['max'].toString()) ?? 0,
      type: json['type'] ?? 'default',
    );
  }

  double calculatePrice(int quantity) {
    return (quantity * rate * 600) / 1000;
  }
}

class Order {
  final int id;
  final String service;
  final int quantity;
  final double price;
  final String link;
  final String status;
  final DateTime date;

  Order({
    required this.id,
    required this.service,
    required this.quantity,
    required this.price,
    required this.link,
    required this.status,
    required this.date,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] ?? 0,
      service: json['service'] ?? '',
      quantity: json['quantite'] ?? 0,
      price: (json['prix'] ?? 0.0).toDouble(),
      link: json['lien'] ?? '',
      status: json['statut'] ?? 'En cours',
      date: DateTime.parse(json['date_commande'] ?? DateTime.now().toString()),
    );
  }
}

// ============================================
// SERVICE API
// ============================================

class ApiService {
  static const String baseUrl = 'https://skyboost.me/api_skyboost.php'; // À MODIFIER
  
  Future<Map<String, dynamic>> request(String action, {Map<String, dynamic>? body}) async {
    try {
      final url = Uri.parse('$baseUrl?action=$action');
      
      final response = body != null
          ? await http.post(url, body: body)
          : await http.get(url);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': 'Erreur serveur: ${response.statusCode}'
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Erreur de connexion: $e'
      };
    }
  }

  // Authentification
  Future<Map<String, dynamic>> login(String email, String password) async {
    return await request('login', body: {
      'email': email,
      'password': password,
    });
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String? referralCode,
  }) async {
    final body = {
      'username': username,
      'email': email,
      'password': password,
      'currency': 'XOF',
    };
    
    if (referralCode != null && referralCode.isNotEmpty) {
      body['referral_code'] = referralCode;
    }
    
    return await request('register', body: body);
  }

  Future<Map<String, dynamic>> checkAuth() async {
    return await request('check_auth');
  }

  // Plateformes
  Future<Map<String, dynamic>> getPlatforms() async {
    return await request('get_platforms');
  }

  // Services
  Future<Map<String, dynamic>> getServices(String platform) async {
    return await request('get_services', body: {'platform': platform});
  }

  // Commandes
  Future<Map<String, dynamic>> createOrder({
    required String serviceId,
    required String link,
    required int quantity,
  }) async {
    return await request('create_order', body: {
      'service_id': serviceId,
      'link': link,
      'quantity': quantity.toString(),
    });
  }

  Future<Map<String, dynamic>> getUserOrders({int limit = 5}) async {
    return await request('get_user_orders', body: {'limit': limit.toString()});
  }

  // Utilisateur
  Future<Map<String, dynamic>> getUserProfile() async {
    return await request('get_user_profile');
  }

  Future<Map<String, dynamic>> getUserBalance() async {
    return await request('get_user_balance');
  }
}

// ============================================
// GESTION D'ÉTAT
// ============================================

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  final ApiService _apiService = ApiService();
  final SharedPreferences _prefs;

  AuthProvider(this._prefs);

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;

  Future<void> loadUser() async {
    final userJson = _prefs.getString('user');
    if (userJson != null) {
      try {
        _user = User.fromJson(jsonDecode(userJson));
        notifyListeners();
      } catch (e) {
        await _prefs.remove('user');
      }
    }
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    final response = await _apiService.login(email, password);

    if (response['success'] == true) {
      final userData = response['data']['user'];
      _user = User.fromJson(userData);
      
      await _prefs.setString('user', jsonEncode(userData));
      await _prefs.setString('session_id', response['data']['session_id'] ?? '');
      
      _isLoading = false;
      notifyListeners();
      return true;
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> register({
    required String username,
    required String email,
    required String password,
    String? referralCode,
  }) async {
    _isLoading = true;
    notifyListeners();

    final response = await _apiService.register(
      username: username,
      email: email,
      password: password,
      referralCode: referralCode,
    );

    if (response['success'] == true) {
      final userData = response['data']['user'];
      _user = User.fromJson(userData);
      
      await _prefs.setString('user', jsonEncode(userData));
      await _prefs.setString('session_id', response['data']['session_id'] ?? '');
      
      _isLoading = false;
      notifyListeners();
      return true;
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    await _prefs.remove('user');
    await _prefs.remove('session_id');
    _user = null;
    notifyListeners();
  }
}

// ============================================
// APPLICATION PRINCIPALE
// ============================================

class SkyBoostApp extends StatelessWidget {
  const SkyBoostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const MaterialApp(
            home: Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        return ChangeNotifierProvider(
          create: (_) => AuthProvider(snapshot.data!),
          child: MaterialApp(
            title: 'SkyBoost',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              primaryColor: const Color(0xFFFF7800),
              primarySwatch: Colors.orange,
              scaffoldBackgroundColor: const Color(0xFFF5F5F5),
              fontFamily: 'Roboto',
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFFFF7800),
                elevation: 2,
                centerTitle: false,
                titleTextStyle: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF7800),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            home: Consumer<AuthProvider>(
              builder: (context, authProvider, _) {
                if (authProvider.isLoading) {
                  return const SplashScreen();
                }
                return authProvider.isAuthenticated 
                    ? const HomeScreen()
                    : const LoginScreen();
              },
            ),
          ),
        );
      },
    );
  }
}

// ============================================
// ÉCRANS
// ============================================

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.rocket_launch,
                size: 80,
                color: Colors.white,
              ),
              const SizedBox(height: 20),
              const Text(
                'SkyBoost',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Boostez vos réseaux sociaux',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _showPassword = false;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.login(
      _emailController.text.trim(),
      _passwordController.text,
    );
    
    setState(() => _isLoading = false);
    
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email ou mot de passe incorrect'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _navigateToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7800),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Icon(
                              Icons.rocket_launch,
                              color: Colors.white,
                              size: 32,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'SkyBoost',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Connexion à votre compte',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                  
                  // Login Card
                  Container(
                    margin: const EdgeInsets.only(top: 20, bottom: 20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.login,
                                color: Color(0xFFFF7800),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Connectez-vous',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          // Email
                          TextFormField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Adresse email',
                              prefixIcon: Icon(Icons.email),
                              hintText: 'Entrez votre email',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Veuillez entrer votre email';
                              }
                              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                                return 'Email invalide';
                              }
                              return null;
                            },
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Password
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Mot de passe',
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showPassword ? Icons.visibility : Icons.visibility_off,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showPassword = !_showPassword;
                                  });
                                },
                              ),
                              hintText: 'Entrez votre mot de passe',
                              border: const OutlineInputBorder(),
                            ),
                            obscureText: !_showPassword,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Veuillez entrer votre mot de passe';
                              }
                              return null;
                            },
                          ),
                          
                          const SizedBox(height: 24),
                          
                           // Login Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.login, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'Se connecter',
                                          style: TextStyle(fontSize: 16),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Links
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Vous n'avez pas de compte ? ",
                                style: TextStyle(color: Colors.grey),
                              ),
                              GestureDetector(
                                onTap: _navigateToRegister,
                                child: const Text(
                                  'Inscrivez-vous',
                                  style: TextStyle(
                                    color: Color(0xFFFF7800),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _referralController = TextEditingController();
  bool _isLoading = false;
  bool _showPassword = false;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.register(
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      referralCode: _referralController.text.trim(),
    );
    
    setState(() => _isLoading = false);
    
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de l\'inscription'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _navigateToLogin() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inscription'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const Icon(
                Icons.person_add,
                size: 80,
                color: Color(0xFFFF7800),
              ),
              const SizedBox(height: 20),
              const Text(
                'Créez votre compte SkyBoost',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Inscrivez-vous en quelques secondes',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 30),
              
              // Username
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Nom d\'utilisateur',
                  prefixIcon: Icon(Icons.person),
                  hintText: 'Entrez votre nom',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer un nom d\'utilisateur';
                  }
                  if (value.length < 3) {
                    return 'Minimum 3 caractères';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // Email
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Adresse email',
                  prefixIcon: Icon(Icons.email),
                  hintText: 'Entrez votre email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer votre email';
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                    return 'Email invalide';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // Password
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _showPassword = !_showPassword;
                      });
                    },
                  ),
                  hintText: 'Choisissez un mot de passe',
                  border: const OutlineInputBorder(),
                ),
                obscureText: !_showPassword,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer un mot de passe';
                  }
                  if (value.length < 6) {
                    return 'Minimum 6 caractères';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // Referral Code
              TextFormField(
                controller: _referralController,
                decoration: const InputDecoration(
                  labelText: 'Code de parrainage (facultatif)',
                  prefixIcon: Icon(Icons.card_giftcard),
                  hintText: 'Code de parrainage',
                  border: OutlineInputBorder(),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Terms
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'En vous inscrivant, vous acceptez nos conditions générales et notre politique de confidentialité.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Register Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'S\'inscrire',
                              style: TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Login Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Déjà un compte ? ',
                    style: TextStyle(color: Colors.grey),
                  ),
                  GestureDetector(
                    onTap: _navigateToLogin,
                    child: const Text(
                      'Connectez-vous',
                      style: TextStyle(
                        color: Color(0xFFFF7800),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _referralController.dispose();
    super.dispose();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _platforms = [];
  List<Order> _recentOrders = [];
  List<Service> _services = [];
  String? _selectedPlatform;
  Service? _selectedService;
  final _linkController = TextEditingController();
  final _quantityController = TextEditingController();
  double _totalPrice = 0.0;
  bool _isLoading = false;
  bool _isOrderLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // Load platforms
      final platformsResponse = await _apiService.getPlatforms();
      if (platformsResponse['success'] == true) {
        _platforms = List<Map<String, dynamic>>.from(platformsResponse['data']);
        if (_platforms.isNotEmpty) {
          _selectedPlatform = _platforms.first['id'];
          await _loadServices(_selectedPlatform!);
        }
      }

      // Load recent orders
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated) {
        final ordersResponse = await _apiService.getUserOrders();
        if (ordersResponse['success'] == true) {
          final ordersData = List<Map<String, dynamic>>.from(ordersResponse['data']);
          _recentOrders = ordersData.map((order) => Order.fromJson(order)).toList();
        }
      }
    } catch (e) {
      print('Error loading data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadServices(String platform) async {
    setState(() => _isLoading = true);
    
    try {
      final response = await _apiService.getServices(platform);
      if (response['success'] == true) {
        final servicesData = List<Map<String, dynamic>>.from(response['data']);
        _services = servicesData.map((service) => Service.fromJson(service)).toList();
      }
    } catch (e) {
      print('Error loading services: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _calculatePrice() {
    if (_selectedService == null || _quantityController.text.isEmpty) {
      setState(() => _totalPrice = 0.0);
      return;
    }
    
    final quantity = int.tryParse(_quantityController.text) ?? 0;
    if (quantity < _selectedService!.min) {
      setState(() => _totalPrice = 0.0);
      return;
    }
    
    final price = _selectedService!.calculatePrice(quantity);
    setState(() => _totalPrice = price);
  }

  Future<void> _createOrder() async {
    if (_selectedService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un service'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_linkController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez entrer un lien'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final quantity = int.tryParse(_quantityController.text) ?? 0;
    if (quantity < _selectedService!.min) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Quantité minimum: ${_selectedService!.min}'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isOrderLoading = true);
    
    try {
      final response = await _apiService.createOrder(
        serviceId: _selectedService!.id,
        link: _linkController.text,
        quantity: quantity,
      );

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Commande passée avec succès !'),
            backgroundColor: Colors.green,
          ),
        );

        // Reset form
        _linkController.clear();
        _quantityController.clear();
        setState(() {
          _selectedService = null;
          _totalPrice = 0.0;
        });

        // Refresh orders
        await _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Erreur lors de la commande'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isOrderLoading = false);
    }
  }

  void _logout() {
    Provider.of<AuthProvider>(context, listen: false).logout();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SkyBoost'),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '${user.balance} FCFA',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bonjour, ${user?.username ?? 'Utilisateur'} !',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Passez une commande pour booster vos réseaux sociaux',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Order Form
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Nouvelle commande',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Platform Selection
                          const Text('Plateforme:'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _platforms.map((platform) {
                              return ChoiceChip(
                                label: Text(platform['name']),
                                selected: _selectedPlatform == platform['id'],
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedPlatform = platform['id'];
                                    _selectedService = null;
                                    _services.clear();
                                    _loadServices(platform['id']);
                                  });
                                },
                                selectedColor: const Color(0xFFFF7800),
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 16),

                          // Service Selection
                          if (_services.isNotEmpty) ...[
                            const Text('Service:'),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<Service>(
                              value: _selectedService,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'Choisir un service',
                              ),
                              items: _services.map((service) {
                                return DropdownMenuItem<Service>(
                                  value: service,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        service.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Min: ${service.min} | Max: ${service.max}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (service) {
                                setState(() {
                                  _selectedService = service;
                                  _calculatePrice();
                                });
                              },
                            ),
                          ],

                          const SizedBox(height: 16),

                          // Link
                          TextFormField(
                            controller: _linkController,
                            decoration: const InputDecoration(
                              labelText: 'Lien',
                              hintText: 'https://...',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.link),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Quantity
                          TextFormField(
                            controller: _quantityController,
                            decoration: const InputDecoration(
                              labelText: 'Quantité',
                              hintText: '100',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.numbers),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _calculatePrice(),
                          ),

                          const SizedBox(height: 16),

                          // Price Display
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Prix total:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${_totalPrice.toStringAsFixed(2)} FCFA',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFF7800),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Submit Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isOrderLoading ? null : _createOrder,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _isOrderLoading
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.send, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'Passer la commande',
                                          style: TextStyle(fontSize: 16),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Recent Orders
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '5 dernières commandes',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Divider(),
                          const SizedBox(height: 8),
                          
                          if (_recentOrders.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'Aucune commande récente',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          else
                            Column(
                              children: _recentOrders.map((order) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey[300]!),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            order.service,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: order.status == 'Terminé'
                                                  ? Colors.green[100]
                                                  : Colors.orange[100],
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              order.status,
                                              style: TextStyle(
                                                color: order.status == 'Terminé'
                                                    ? Colors.green[800]
                                                    : Colors.orange[800],
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Lien: ${order.link.substring(0, min(30, order.link.length))}...',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Quantité: ${order.quantity}',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          Text(
                                            '${order.price} FCFA',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(order.date)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}

