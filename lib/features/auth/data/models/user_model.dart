import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String userId;
  final String name;
  final String email;
  final DateTime createdAt;

  const UserModel({
    required this.userId,
    required this.name,
    required this.email,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'email': email,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  static UserModel fromDoc({
    required String userId,
    required Map<String, dynamic> data,
  }) {
    final createdAtTs = data['createdAt'];
    final createdAt = createdAtTs is Timestamp ? createdAtTs.toDate() : DateTime.now();
    return UserModel(
      userId: userId,
      name: (data['name'] ?? '') as String,
      email: (data['email'] ?? '') as String,
      createdAt: createdAt,
    );
  }
}

