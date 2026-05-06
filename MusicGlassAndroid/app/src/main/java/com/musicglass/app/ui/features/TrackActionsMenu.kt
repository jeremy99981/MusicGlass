package com.musicglass.app.ui.features

import androidx.compose.foundation.layout.Box
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue

@Composable
fun TrackActionsMenu(
    onPlay: () -> Unit,
    onRadio: () -> Unit,
    onFavorite: (() -> Unit)? = null
) {
    var expanded by remember { mutableStateOf(false) }

    Box {
        IconButton(onClick = { expanded = true }) {
            Icon(
                Icons.Filled.MoreVert,
                contentDescription = "Options",
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            DropdownMenuItem(
                text = { Text("Ajouter aux favoris") },
                leadingIcon = {
                    Icon(Icons.Filled.FavoriteBorder, contentDescription = null)
                },
                onClick = {
                    expanded = false
                    onFavorite?.invoke()
                }
            )
            DropdownMenuItem(
                text = { Text("Lecture") },
                leadingIcon = {
                    Icon(Icons.Filled.PlayArrow, contentDescription = null)
                },
                onClick = {
                    expanded = false
                    onPlay()
                }
            )
            DropdownMenuItem(
                text = { Text("Lancer la radio") },
                leadingIcon = {
                    Icon(Icons.Filled.GraphicEq, contentDescription = null)
                },
                onClick = {
                    expanded = false
                    onRadio()
                }
            )
        }
    }
}
