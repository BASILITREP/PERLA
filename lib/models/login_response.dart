class LoginResponse{
  final int userId;
  final String firstName;
  final String lastName;
  final String? jwtToken;

  LoginResponse({
    required this.userId,
    required this.firstName,
    required this.lastName,
    this.jwtToken,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      userId: json['userId'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      jwtToken: json['jwtToken'],
    );
  }
}