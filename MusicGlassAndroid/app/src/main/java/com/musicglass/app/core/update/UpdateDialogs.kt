package com.musicglass.app.core.update

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.NewReleases
import androidx.compose.material.icons.filled.Rocket
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * Material Design 3 dialog shown when a new update is available.
 * Shows release name, version comparison, release notes, and a download button.
 */
@Composable
fun UpdateAvailableDialog(
    updateInfo: UpdateInfo,
    downloadState: UpdateCheckState,
    downloadProgress: Float,
    onDownload: () -> Unit,
    onDismiss: () -> Unit
) {
    val isDownloading = downloadState is UpdateCheckState.Downloading
    val animatedProgress by animateFloatAsState(
        targetValue = downloadProgress,
        animationSpec = tween(300),
        label = "downloadProgress"
    )

    AlertDialog(
        onDismissRequest = {
            if (!isDownloading) onDismiss()
        },
        icon = {
            Icon(
                imageVector = Icons.Filled.SystemUpdate,
                contentDescription = null,
                modifier = Modifier.size(32.dp),
                tint = MaterialTheme.colorScheme.primary
            )
        },
        title = {
            Text(
                text = "Mise à jour disponible",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
        },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
            ) {
                // Version badge
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    VersionBadge(
                        label = "Actuelle",
                        version = updateInfo.currentVersion,
                        isPrimary = false
                    )
                    Spacer(Modifier.width(12.dp))
                    Icon(
                        imageVector = Icons.Filled.Rocket,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(Modifier.width(12.dp))
                    VersionBadge(
                        label = "Nouvelle",
                        version = updateInfo.latestVersion,
                        isPrimary = true
                    )
                }

                Spacer(Modifier.height(16.dp))

                // Release name
                if (!updateInfo.releaseName.isBlank()) {
                    Text(
                        text = updateInfo.releaseName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Spacer(Modifier.height(8.dp))
                }

                // Release notes
                if (updateInfo.releaseNotes.isNotBlank()) {
                    Text(
                        text = "Nouveautés :",
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = updateInfo.releaseNotes,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                // Download progress
                AnimatedVisibility(
                    visible = isDownloading,
                    enter = fadeIn() + slideInVertically(),
                    exit = fadeOut()
                ) {
                    Column(modifier = Modifier.padding(top = 16.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(
                                "Téléchargement en cours…",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Text(
                                "${(animatedProgress * 100).toInt()}%",
                                style = MaterialTheme.typography.bodySmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                        Spacer(Modifier.height(8.dp))
                        LinearProgressIndicator(
                            progress = animatedProgress,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(6.dp)
                                .clip(MaterialTheme.shapes.small),
                            color = MaterialTheme.colorScheme.primary,
                            trackColor = MaterialTheme.colorScheme.surfaceVariant,
                        )
                    }
                }

                // Error message
                if (downloadState is UpdateCheckState.Error) {
                    Spacer(Modifier.height(12.dp))
                    Text(
                        text = downloadState.message,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = onDownload,
                enabled = !isDownloading,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary
                )
            ) {
                if (isDownloading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                    Spacer(Modifier.width(8.dp))
                    Text("Téléchargement…")
                } else {
                    Icon(Icons.Filled.Download, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Télécharger")
                }
            }
        },
        dismissButton = {
            if (!isDownloading) {
                TextButton(onClick = onDismiss) {
                    Text("Plus tard")
                }
            }
        }
    )
}

/**
 * Material Design 3 dialog shown once after the user installs a new version,
 * displaying what changed (changelog from the release notes).
 */
@Composable
fun ChangelogDialog(
    versionName: String,
    releaseNotes: String,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(
                imageVector = Icons.Filled.NewReleases,
                contentDescription = null,
                modifier = Modifier.size(32.dp),
                tint = MaterialTheme.colorScheme.primary
            )
        },
        title = {
            Text(
                text = "Bienvenue dans la version $versionName !",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
        },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
            ) {
                if (releaseNotes.isNotBlank()) {
                    Text(
                        text = "Voici les nouveautés :",
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        text = releaseNotes,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    Text(
                        text = "L'application a été mise à jour avec succès.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        },
        confirmButton = {
            Button(onClick = onDismiss) {
                Text("C'est parti !")
            }
        }
    )
}

/**
 * Small version badge chip used in the update dialog.
 */
@Composable
private fun VersionBadge(
    label: String,
    version: String,
    isPrimary: Boolean
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(2.dp))
        Text(
            text = version,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = if (isPrimary) MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}
