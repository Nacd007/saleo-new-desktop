import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'desktop_security.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RegistrationTicket {
  const RegistrationTicket({required this.id, required this.email});
  final String id;
  final String email;
}

class CompanyPreview {
  CompanyPreview({
    required this.companyId,
    required this.name,
    this.logoUrl,
    ReceiptTemplate? receiptTemplate,
    ReceiptTemplateSettings? receiptTemplates,
  }) : receiptTemplates =
           receiptTemplates ??
           (receiptTemplate == null
               ? ReceiptTemplateSettings.forCompany(name)
               : ReceiptTemplateSettings(
                   defaultTemplate: ReceiptTemplate.defaults(name),
                   customTemplate: receiptTemplate,
                   active: ReceiptTemplateKind.custom,
                 ));
  final String companyId;
  final String name;
  final String? logoUrl;
  final ReceiptTemplateSettings receiptTemplates;
  ReceiptTemplate get receiptTemplate => receiptTemplates.activeTemplate;

  factory CompanyPreview.fromJson(Map<String, dynamic> json) {
    final name = json['name'].toString();
    return CompanyPreview(
      companyId: json['company_id'].toString(),
      name: name,
      logoUrl: json['logo_url']?.toString(),
      receiptTemplates: ReceiptTemplateSettings.fromJson(
        (json['receipt_templates'] as Map?)?.cast<String, dynamic>(),
        companyName: name,
        legacyActiveTemplate: (json['receipt_template'] as Map?)
            ?.cast<String, dynamic>(),
      ),
    );
  }
}

class AuthenticatedMember {
  const AuthenticatedMember({
    required this.token,
    required this.username,
    required this.displayName,
    required this.role,
    required this.company,
    this.jobTitle = 'Receptionist',
  });
  final String token;
  final String username;
  final String displayName;
  final UserRole role;
  final CompanyPreview company;
  final String jobTitle;

  Map<String, dynamic> toJson() => {
    'token': token,
    'username': username,
    'display_name': displayName,
    'role': role.name,
    'job_title': jobTitle,
    'company': {
      'company_id': company.companyId,
      'name': company.name,
      'logo_url': company.logoUrl,
      'receipt_template': company.receiptTemplate.toJson(),
      'receipt_templates': company.receiptTemplates.toJson(),
    },
  };

  factory AuthenticatedMember.fromJson(Map<String, dynamic> json) {
    final role = json['role'] == 'admin'
        ? UserRole.admin
        : UserRole.receptionist;
    return AuthenticatedMember(
      token: json['token'].toString(),
      username: json['username'].toString(),
      displayName: json['display_name'].toString(),
      role: role,
      jobTitle: json['job_title']?.toString().trim().isNotEmpty == true
          ? json['job_title'].toString().trim()
          : role == UserRole.admin
          ? 'Administrator'
          : 'Receptionist',
      company: CompanyPreview.fromJson(
        (json['company'] as Map).cast<String, dynamic>(),
      ),
    );
  }
}

class StaffMember {
  const StaffMember({
    required this.id,
    required this.username,
    required this.displayName,
    required this.active,
    this.archivedAt,
    this.recoverUntil,
    this.jobTitle = 'Receptionist',
    this.photoBytes,
  });

  final int id;
  final String username;
  final String displayName;
  final bool active;
  final DateTime? archivedAt;
  final DateTime? recoverUntil;
  final String jobTitle;
  final Uint8List? photoBytes;
  bool get isArchived => archivedAt != null;
  bool get canRecover =>
      recoverUntil != null && recoverUntil!.isAfter(DateTime.now().toUtc());

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
    id: json['id'] as int,
    username: json['username'].toString(),
    displayName: json['display_name'].toString(),
    active: json['active'] == true,
    photoBytes: json['photo_base64'] == null
        ? null
        : base64Decode(json['photo_base64'].toString()),
    jobTitle: json['job_title']?.toString().trim().isNotEmpty == true
        ? json['job_title'].toString().trim()
        : 'Receptionist',
    archivedAt: json['archived_at'] == null
        ? null
        : DateTime.parse(json['archived_at'].toString()),
    recoverUntil: json['recover_until'] == null
        ? null
        : DateTime.parse(json['recover_until'].toString()),
  );
}

class AuthService {
  AuthService({http.Client? client}) : _client = client ?? http.Client() {
    validateServerConfiguration(
      _baseUrl,
      const String.fromEnvironment(
        'SYNC_API_URL',
        defaultValue: 'https://api.naprojekts.xyz',
      ),
    );
  }

  static const _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.naprojekts.xyz',
  );
  static const _storage = FlutterSecureStorage();
  static const _sessionKey = 'saleo_new_desktop.auth.session.v1';
  final http.Client _client;
  String? _sessionToken;

  Uri _uri(String path) =>
      Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}$path');

  Future<RegistrationTicket> register({
    required DateTime dateOfBirth,
    required String username,
    required String email,
    required String countryCode,
    required String phoneNumber,
    required String password,
  }) async {
    final data = await _request(
      'POST',
      '/api/v1/auth/register',
      body: {
        'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
        'username': username.trim(),
        'email': email.trim(),
        'phone_country_code': countryCode,
        'phone_number': phoneNumber.trim(),
        'password': password,
      },
    );
    return RegistrationTicket(
      id: data['registration_id'].toString(),
      email: data['email'].toString(),
    );
  }

  Future<bool> isEmailVerified(String registrationId) async {
    final data = await _request(
      'GET',
      '/api/v1/auth/verification-status?registration_id=${Uri.encodeQueryComponent(registrationId)}',
    );
    return data['verified'] == true;
  }

  Future<void> resendVerification(String registrationId) => _request(
    'POST',
    '/api/v1/auth/resend-verification',
    body: {'registration_id': registrationId},
  );

  Future<void> setRegistrationPin(String registrationId, String pin) =>
      _request(
        'POST',
        '/api/v1/auth/set-pin',
        body: {'registration_id': registrationId, 'pin': pin},
      );

  Future<void> recoverCompanyId(String email) => _request(
    'POST',
    '/api/v1/auth/recover-company-id',
    body: {'email': email.trim()},
  );

  Future<void> requestAdminPinReset(String email) => _request(
    'POST',
    '/api/v1/auth/request-admin-pin-reset',
    body: {'email': email.trim()},
  );

  Future<AuthenticatedMember> createCompany({
    required String registrationId,
    required String companyName,
    required String country,
    String? requestedCompanyId,
    Uint8List? logoBytes,
  }) async {
    final data = await _request(
      'POST',
      '/api/v1/companies',
      body: {
        'registration_id': registrationId,
        'name': companyName.trim(),
        'country': country,
        if (requestedCompanyId?.trim().isNotEmpty == true)
          'requested_company_id': requestedCompanyId!.trim().toUpperCase(),
        if (logoBytes != null) 'logo_base64': base64Encode(logoBytes),
      },
    );
    final member = AuthenticatedMember.fromJson(data);
    await saveSession(member);
    return member;
  }

  Future<CompanyPreview> findCompany(String companyId) async {
    final data = await _request(
      'GET',
      '/api/v1/companies/${Uri.encodeComponent(companyId.trim().toUpperCase())}',
    );
    return CompanyPreview.fromJson(data);
  }

  Future<AuthenticatedMember> login({
    required String companyId,
    required String username,
    required String pin,
  }) async {
    final data = await _request(
      'POST',
      '/api/v1/auth/login',
      body: {
        'company_id': companyId.trim().toUpperCase(),
        'username': username.trim(),
        'pin': pin,
      },
    );
    final member = AuthenticatedMember.fromJson(data);
    await saveSession(member);
    return member;
  }

  Future<AuthenticatedMember> updateAdminUsername(String username) async {
    final data = await _request(
      'PATCH',
      '/api/v1/auth/admin-account',
      authenticated: true,
      body: {'username': username.trim()},
    );
    final member = AuthenticatedMember.fromJson(data);
    await saveSession(member);
    return member;
  }

  Future<List<StaffMember>> getStaff() async {
    final data = await _request('GET', '/api/v1/staff', authenticated: true);
    return (data['staff'] as List<dynamic>? ?? const [])
        .map(
          (item) => StaffMember.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<StaffMember> createStaff({
    required String username,
    required String displayName,
    required String pin,
    required String jobTitle,
  }) async {
    final data = await _request(
      'POST',
      '/api/v1/staff',
      authenticated: true,
      body: {
        'username': username.trim(),
        'display_name': displayName.trim(),
        'pin': pin,
        'job_title': jobTitle.trim(),
      },
    );
    return StaffMember.fromJson(data);
  }

  Future<void> inviteStaff(String email, {required String jobTitle}) =>
      _request(
        'POST',
        '/api/v1/staff/invitations',
        authenticated: true,
        body: {'email': email.trim(), 'job_title': jobTitle.trim()},
      );

  Future<StaffMember> updateStaff(
    StaffMember staff, {
    Uint8List? photoBytes,
    bool updatePhoto = false,
  }) async {
    final data = await _request(
      'PATCH',
      '/api/v1/staff/${staff.id}',
      authenticated: true,
      body: {
        'username': staff.username,
        'display_name': staff.displayName,
        'active': staff.active,
        'job_title': staff.jobTitle,
        if (updatePhoto)
          'photo_base64': photoBytes == null ? null : base64Encode(photoBytes),
      },
    );
    if (updatePhoto && !data.containsKey('photo_base64')) {
      throw const AuthException(
        'Staff photos require the updated backend. The photo was not uploaded.',
      );
    }
    return StaffMember.fromJson(data);
  }

  Future<StaffMember> archiveStaff(int staffId) async {
    final data = await _request(
      'DELETE',
      '/api/v1/staff/$staffId',
      authenticated: true,
    );
    return StaffMember.fromJson(data);
  }

  Future<StaffMember> restoreStaff(int staffId) async {
    final data = await _request(
      'POST',
      '/api/v1/staff/$staffId/restore',
      authenticated: true,
    );
    return StaffMember.fromJson(data);
  }

  Future<void> resetStaffPin(int staffId, String pin) => _request(
    'POST',
    '/api/v1/staff/$staffId/reset-pin',
    authenticated: true,
    body: {'pin': pin},
  );

  Future<ReceiptTemplateSettings> updateReceiptTemplate(
    ReceiptTemplate template,
  ) async {
    final data = await _request(
      'PATCH',
      '/api/v1/company/receipt-template',
      authenticated: true,
      body: template.toJson(),
    );
    final saved = ReceiptTemplateSettings.fromJson(
      (data['receipt_templates'] as Map?)?.cast<String, dynamic>(),
      companyName: template.shopName,
      legacyActiveTemplate: (data['receipt_template'] as Map?)
          ?.cast<String, dynamic>(),
    );
    final member = await loadSession();
    if (member != null) {
      await saveSession(
        AuthenticatedMember(
          token: member.token,
          username: member.username,
          displayName: member.displayName,
          role: member.role,
          company: CompanyPreview(
            companyId: member.company.companyId,
            name: member.company.name,
            logoUrl: member.company.logoUrl,
            receiptTemplates: saved,
          ),
        ),
      );
    }
    return saved;
  }

  Future<ReceiptTemplateSettings> selectReceiptTemplate(
    ReceiptTemplateKind selection, {
    required String companyName,
  }) async {
    final data = await _request(
      'PATCH',
      '/api/v1/company/receipt-template/active',
      authenticated: true,
      body: {'active': selection.apiValue},
    );
    final saved = ReceiptTemplateSettings.fromJson(
      (data['receipt_templates'] as Map?)?.cast<String, dynamic>(),
      companyName: companyName,
      legacyActiveTemplate: (data['receipt_template'] as Map?)
          ?.cast<String, dynamic>(),
    );
    final member = await loadSession();
    if (member != null) {
      await saveSession(
        AuthenticatedMember(
          token: member.token,
          username: member.username,
          displayName: member.displayName,
          role: member.role,
          company: CompanyPreview(
            companyId: member.company.companyId,
            name: member.company.name,
            logoUrl: member.company.logoUrl,
            receiptTemplates: saved,
          ),
        ),
      );
    }
    return saved;
  }

  Future<void> saveSession(AuthenticatedMember member) {
    _sessionToken = member.token;
    return _storage.write(key: _sessionKey, value: jsonEncode(member.toJson()));
  }

  Future<AuthenticatedMember?> loadSession() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final member = AuthenticatedMember.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
      _sessionToken = member.token;
      return member;
    } catch (_) {
      await clearSession();
      return null;
    }
  }

  Future<void> clearSession() {
    _sessionToken = null;
    return _storage.delete(key: _sessionKey);
  }

  /// Revoke only this device's token before removing the saved session.
  /// Failure is surfaced: do not claim that a server session was revoked offline.
  Future<void> revokeCurrentSession() async {
    if (_sessionToken == null || _sessionToken!.isEmpty) return;
    await _request('POST', '/api/v1/auth/logout', authenticated: true);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    try {
      final headers = {'accept': 'application/json'};
      if (authenticated) {
        if (_sessionToken == null || _sessionToken!.isEmpty) {
          throw const AuthException('Sign in again to continue.');
        }
        headers['authorization'] = 'Bearer $_sessionToken';
      }
      http.Response response;
      if (method == 'POST') {
        headers['content-type'] = 'application/json';
        response = await _client
            .post(_uri(path), headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 20));
      } else if (method == 'PATCH') {
        headers['content-type'] = 'application/json';
        response = await _client
            .patch(_uri(path), headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 20));
      } else {
        response = await _client
            .get(_uri(path), headers: headers)
            .timeout(const Duration(seconds: 20));
      }
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(response.body) as Map).cast<String, dynamic>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthException(
          decoded['message']?.toString() ??
              decoded['detail']?.toString() ??
              'The request could not be completed.',
        );
      }
      return decoded;
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Saleo could not reach the server. Check your connection and try again.',
      );
    }
  }
}
