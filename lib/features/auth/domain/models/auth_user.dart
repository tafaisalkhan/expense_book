class AuthUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool isLoggedIn;
  final String? loggedOutNotice;
  final bool requiresLogoutDialog;
  final String? logoutDialogReason;

  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.isLoggedIn = false,
    this.loggedOutNotice,
    this.requiresLogoutDialog = false,
    this.logoutDialogReason,
  });

  factory AuthUser.anonymous({String? notice}) {
    return AuthUser(
      uid: '',
      email: null,
      displayName: null,
      photoUrl: null,
      isLoggedIn: false,
      loggedOutNotice: notice,
      requiresLogoutDialog: false,
      logoutDialogReason: null,
    );
  }

  AuthUser copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    bool? isLoggedIn,
    String? loggedOutNotice,
    bool? requiresLogoutDialog,
    String? logoutDialogReason,
  }) {
    return AuthUser(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      loggedOutNotice: loggedOutNotice ?? this.loggedOutNotice,
      requiresLogoutDialog: requiresLogoutDialog ?? this.requiresLogoutDialog,
      logoutDialogReason: logoutDialogReason ?? this.logoutDialogReason,
    );
  }
}
