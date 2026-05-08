package com.musicglass.app.ui.features.auth

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch

enum class AuthMode {
    SignIn, SignUp
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountAuthScreen(
    onBack: () -> Unit,
    onSuccess: () -> Unit = {}
) {
    var authMode by rememberSaveable { mutableStateOf(AuthMode.SignIn) }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    
    // Form States
    var fullName by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var confirmPassword by rememberSaveable { mutableStateOf("") }
    
    var isPasswordVisible by rememberSaveable { mutableStateOf(false) }
    var isConfirmPasswordVisible by rememberSaveable { mutableStateOf(false) }
    var isLoading by rememberSaveable { mutableStateOf(false) }
    
    // Validation States
    var emailError by remember { mutableStateOf<String?>(null) }
    var passwordError by remember { mutableStateOf<String?>(null) }
    var fullNameError by remember { mutableStateOf<String?>(null) }
    var confirmPasswordError by remember { mutableStateOf<String?>(null) }

    val focusManager = LocalFocusManager.current

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Retour")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent
                )
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(24.dp))
            
            AnimatedContent(
                targetState = authMode,
                transitionSpec = {
                    fadeIn(animationSpec = tween(300)) togetherWith fadeOut(animationSpec = tween(300))
                },
                label = "TitleAnimation"
            ) { mode ->
                Text(
                    text = if (mode == AuthMode.SignIn) "Connexion" else "Créer un compte",
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center
                )
            }
            
            Spacer(modifier = Modifier.height(12.dp))
            
            Text(
                text = "Retrouvez vos playlists et votre historique sur tous vos appareils.",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
            
            Spacer(modifier = Modifier.height(32.dp))
            
            // Custom Segmented Control
            AuthSegmentedControl(
                selectedMode = authMode,
                onModeSelected = { 
                    authMode = it
                    // Clear errors on mode switch
                    emailError = null
                    passwordError = null
                    fullNameError = null
                    confirmPasswordError = null
                }
            )
            
            Spacer(modifier = Modifier.height(32.dp))
            
            // Auth Card
            ElevatedCard(
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.extraLarge,
                colors = CardDefaults.elevatedCardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                )
            ) {
                Column(
                    modifier = Modifier.padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    if (authMode == AuthMode.SignUp) {
                        AuthTextField(
                            value = fullName,
                            onValueChange = { fullName = it; fullNameError = null },
                            label = "Nom complet",
                            icon = Icons.Default.Person,
                            isError = fullNameError != null,
                            supportingText = fullNameError
                        )
                    }
                    
                    AuthTextField(
                        value = email,
                        onValueChange = { email = it; emailError = null },
                        label = "Adresse e-mail",
                        icon = Icons.Default.Email,
                        keyboardType = KeyboardType.Email,
                        isError = emailError != null,
                        supportingText = emailError
                    )
                    
                    AuthTextField(
                        value = password,
                        onValueChange = { password = it; passwordError = null },
                        label = "Mot de passe",
                        icon = Icons.Default.Lock,
                        keyboardType = KeyboardType.Password,
                        isPassword = true,
                        passwordVisible = isPasswordVisible,
                        onPasswordToggle = { isPasswordVisible = !isPasswordVisible },
                        isError = passwordError != null,
                        supportingText = passwordError
                    )
                    
                    if (authMode == AuthMode.SignUp) {
                        AuthTextField(
                            value = confirmPassword,
                            onValueChange = { confirmPassword = it; confirmPasswordError = null },
                            label = "Confirmer le mot de passe",
                            icon = Icons.Default.Lock,
                            keyboardType = KeyboardType.Password,
                            isPassword = true,
                            passwordVisible = isConfirmPasswordVisible,
                            onPasswordToggle = { isConfirmPasswordVisible = !isConfirmPasswordVisible },
                            isError = confirmPasswordError != null,
                            supportingText = confirmPasswordError,
                            imeAction = ImeAction.Done,
                            onAction = { focusManager.clearFocus() }
                        )
                    } else {
                        Text(
                            text = "Mot de passe oublié ?",
                            color = Color(0xFFC26E7A),
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .align(Alignment.End)
                                .clickable {
                                    scope.launch {
                                        snackbarHostState.showSnackbar("Réinitialisation bientôt disponible")
                                    }
                                }
                        )
                    }
                }
            }
            
            Spacer(modifier = Modifier.height(32.dp))
            
            // Primary Button
            AuthPrimaryButton(
                text = if (authMode == AuthMode.SignIn) "Se connecter" else "Créer mon compte",
                isLoading = isLoading,
                onClick = {
                    // Simple validation
                    var hasError = false
                    if (email.isEmpty() || !email.contains("@")) {
                        emailError = "Adresse e-mail invalide"
                        hasError = true
                    }
                    if (password.length < 6) {
                        passwordError = "Le mot de passe doit faire au moins 6 caractères"
                        hasError = true
                    }
                    if (authMode == AuthMode.SignUp) {
                        if (fullName.isEmpty()) {
                            fullNameError = "Veuillez entrer votre nom"
                            hasError = true
                        }
                        if (password != confirmPassword) {
                            confirmPasswordError = "Les mots de passe ne correspondent pas"
                            hasError = true
                        }
                    }
                    
                    if (!hasError) {
                        scope.launch {
                            snackbarHostState.showSnackbar("Connexion MusicGlass bientôt disponible")
                        }
                    }
                }
            )
            
            Spacer(modifier = Modifier.height(24.dp))
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Divider(modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.outlineVariant)
                Text(
                    text = "Ou continuer avec",
                    modifier = Modifier.padding(horizontal = 16.dp),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Divider(modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.outlineVariant)
            }
            
            Spacer(modifier = Modifier.height(24.dp))
            
            // Social Providers
            SocialAuthButton(
                text = "Continuer avec Google",
                icon = Icons.Default.GTranslate, // Simplified for now
                onClick = {
                    scope.launch {
                        snackbarHostState.showSnackbar("Connexion Google bientôt disponible")
                    }
                }
            )
            
            Spacer(modifier = Modifier.height(12.dp))
            
            SocialAuthButton(
                text = "Continuer avec Apple",
                icon = Icons.Default.PhoneIphone,
                onClick = {
                    scope.launch {
                        snackbarHostState.showSnackbar("Connexion Apple bientôt disponible")
                    }
                }
            )
            
            if (authMode == AuthMode.SignUp) {
                Spacer(modifier = Modifier.height(32.dp))
                Text(
                    text = "En créant un compte, vous acceptez nos Conditions d'utilisation et notre Politique de confidentialité.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 16.dp)
                )
            }
            
            Spacer(modifier = Modifier.height(48.dp))
        }
    }
}

@Composable
private fun AuthSegmentedControl(
    selectedMode: AuthMode,
    onModeSelected: (AuthMode) -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(54.dp)
            .padding(horizontal = 4.dp),
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceVariant
    ) {
        Row(modifier = Modifier.fillMaxSize()) {
            AuthSegmentItem(
                text = "Connexion",
                isSelected = selectedMode == AuthMode.SignIn,
                modifier = Modifier.weight(1f),
                onClick = { onModeSelected(AuthMode.SignIn) }
            )
            AuthSegmentItem(
                text = "Inscription",
                isSelected = selectedMode == AuthMode.SignUp,
                modifier = Modifier.weight(1f),
                onClick = { onModeSelected(AuthMode.SignUp) }
            )
        }
    }
}

@Composable
private fun AuthSegmentItem(
    text: String,
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Box(
        modifier = modifier
            .fillMaxHeight()
            .padding(4.dp)
            .clip(CircleShape)
            .background(if (isSelected) MaterialTheme.colorScheme.surface else Color.Transparent)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
            color = if (isSelected) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun AuthTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    icon: ImageVector,
    keyboardType: KeyboardType = KeyboardType.Text,
    isPassword: Boolean = false,
    passwordVisible: Boolean = false,
    onPasswordToggle: () -> Unit = {},
    isError: Boolean = false,
    supportingText: String? = null,
    imeAction: ImeAction = ImeAction.Next,
    onAction: () -> Unit = {}
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        leadingIcon = { Icon(icon, contentDescription = null) },
        trailingIcon = if (isPassword) {
            {
                IconButton(onClick = onPasswordToggle) {
                    Icon(
                        imageVector = if (passwordVisible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                        contentDescription = if (passwordVisible) "Masquer le mot de passe" else "Afficher le mot de passe"
                    )
                }
            }
        } else null,
        visualTransformation = if (isPassword && !passwordVisible) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = imeAction),
        keyboardActions = KeyboardActions(onAny = { onAction() }),
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        isError = isError,
        supportingText = supportingText?.let { { Text(it) } },
        singleLine = true
    )
}

@Composable
private fun AuthPrimaryButton(
    text: String,
    isLoading: Boolean,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(CircleShape)
            .background(
                brush = Brush.linearGradient(
                    colors = listOf(Color(0xFFC26E7A), Color(0xFF8E44AD))
                ),
                shape = CircleShape
            ),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color.Transparent
        ),
        contentPadding = PaddingValues(0.dp)
    ) {
        if (isLoading) {
            CircularProgressIndicator(color = Color.White, modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
        } else {
            Text(text = text, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = Color.White)
        }
    }
}

@Composable
private fun SocialAuthButton(
    text: String,
    icon: ImageVector,
    onClick: () -> Unit
) {
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp),
        shape = CircleShape,
        colors = ButtonDefaults.outlinedButtonColors(
            contentColor = MaterialTheme.colorScheme.onSurface
        )
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(24.dp))
        Spacer(modifier = Modifier.width(12.dp))
        Text(text = text, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
    }
}
