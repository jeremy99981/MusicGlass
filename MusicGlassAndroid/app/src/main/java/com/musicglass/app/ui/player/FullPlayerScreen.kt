package com.musicglass.app.ui.player

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.FormatListBulleted
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.VolumeDown
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.musicglass.app.playback.PlayerViewModel
import com.musicglass.app.playback.RepeatMode
import com.musicglass.app.youtubemusic.bestThumbnailUrl
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max

@Composable
fun FullPlayerDialog(
    viewModel: PlayerViewModel,
    onDismiss: () -> Unit,
    onArtistClick: (String, String?) -> Unit = { _, _ -> }
) {
    val currentTrack by viewModel.currentTrack.collectAsState()
    val currentSongInfo by viewModel.currentSongInfo.collectAsState()

    if (currentTrack == null && currentSongInfo == null) return

    BackHandler(onBack = onDismiss)

    FullPlayerScreen(
        viewModel = viewModel,
        onDismiss = onDismiss,
        onArtistClick = onArtistClick
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FullPlayerScreen(
    viewModel: PlayerViewModel,
    onDismiss: () -> Unit,
    onArtistClick: (String, String?) -> Unit
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    val currentTrack by viewModel.currentTrack.collectAsState()
    val currentSongInfo by viewModel.currentSongInfo.collectAsState()
    val isPlaying by viewModel.isPlaying.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val error by viewModel.error.collectAsState()
    val recoveryStatus by viewModel.recoveryStatus.collectAsState()
    val positionMs by viewModel.positionMs.collectAsState()
    val durationMs by viewModel.durationMs.collectAsState()
    val volume by viewModel.volume.collectAsState()
    val repeatMode by viewModel.repeatMode.collectAsState()
    val shuffleEnabled by viewModel.shuffleEnabled.collectAsState()
    val canSkipNext by viewModel.canSkipNext.collectAsState()
    val canSkipPrevious by viewModel.canSkipPrevious.collectAsState()

    val artworkUrl = resolvedArtworkUrl(
        albumArtwork = currentSongInfo?.album?.thumbnails?.bestThumbnailUrl(),
        songArtwork = currentSongInfo?.thumbnails?.bestThumbnailUrl(),
        payloadArtwork = currentTrack?.thumbnails?.bestThumbnailUrl()
    )?.highResolutionArtworkUrl()
    val title = currentSongInfo?.title?.takeIf { it.isNotBlank() }
        ?: currentTrack?.title?.takeIf { it.isNotBlank() }
        ?: "Aucun titre"
    val subtitle = currentSongInfo?.artists
        ?.joinToString(", ") { it.name.trim() }
        ?.takeIf { it.isNotBlank() }
        ?: currentTrack?.author?.takeIf { !it.isNullOrBlank() }
        ?: "MusicGlass"
    val primaryArtist = currentSongInfo?.artists
        ?.firstOrNull { it.name.isNotBlank() }
    val primaryArtistName = primaryArtist?.name?.trim()
        ?: subtitle.takeIf { it.isNotBlank() && it != "MusicGlass" }
    val primaryArtistBrowseId = primaryArtist?.browseId?.takeIf { it.isNotBlank() }
    val statusMessage = when {
        !recoveryStatus.isNullOrBlank() -> recoveryStatus
        !error.isNullOrBlank() -> error
        isLoading && isPlaying -> "Mise en mémoire"
        isLoading -> "Préparation du flux"
        else -> null
    }

    var sliderPosition by remember { mutableFloatStateOf(0f) }
    var isSeeking by remember { mutableStateOf(false) }
    var dragOffsetPx by remember { mutableFloatStateOf(0f) }
    var showQueue by remember { mutableStateOf(false) }
    var showLyrics by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    val lyricsSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    val dismissThresholdPx = with(density) { 118.dp.toPx() }

    LaunchedEffect(positionMs, durationMs, isSeeking) {
        if (!isSeeking) {
            sliderPosition = positionMs.coerceIn(0L, max(durationMs, 0L)).toFloat()
        }
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .graphicsLayer {
                translationY = dragOffsetPx.coerceAtLeast(0f)
                clip = true
            }
            .background(Color(0xFF111A1A))
            .pointerInput(Unit) {
                detectVerticalDragGestures(
                    onVerticalDrag = { _, dragAmount ->
                        dragOffsetPx = (dragOffsetPx + dragAmount).coerceAtLeast(0f)
                    },
                    onDragEnd = {
                        if (dragOffsetPx > dismissThresholdPx) {
                            onDismiss()
                        } else {
                            dragOffsetPx = 0f
                        }
                    },
                    onDragCancel = {
                        dragOffsetPx = 0f
                    }
                )
            }
    ) {
        val isUltraCompact = maxHeight < 680.dp
        val isVeryCompact = maxHeight < 780.dp
        val isCompact = maxHeight < 880.dp
        val horizontalPadding = if (isUltraCompact) 20.dp else if (isVeryCompact) 22.dp else if (isCompact) 26.dp else 30.dp
        val topContentPadding = if (isUltraCompact) 4.dp else if (isVeryCompact) 6.dp else 8.dp
        val bottomContentPadding = if (isUltraCompact) 6.dp else if (isVeryCompact) 10.dp else 12.dp
        val handleSpacer = if (isUltraCompact) 0.dp else if (isVeryCompact) 2.dp else 6.dp
        val artworkSpacer = if (isUltraCompact) 6.dp else if (isVeryCompact) 8.dp else if (isCompact) 12.dp else 16.dp
        val sliderSpacer = if (isUltraCompact) 4.dp else if (isVeryCompact) 6.dp else 10.dp
        val controlsTopSpacer = if (isUltraCompact) 4.dp else if (isVeryCompact) 6.dp else if (isCompact) 10.dp else 0.dp
        val controlsBottomSpacer = if (isUltraCompact) 4.dp else if (isVeryCompact) 6.dp else if (isCompact) 12.dp else 22.dp
        val bottomActionsSpacer = if (isUltraCompact) 4.dp else if (isVeryCompact) 6.dp else 12.dp
        val playButtonSize = if (isUltraCompact) 78.dp else if (isVeryCompact) 84.dp else if (isCompact) 90.dp else 96.dp
        val playIconSize = if (isUltraCompact) 42.dp else if (isVeryCompact) 46.dp else if (isCompact) 50.dp else 52.dp
        val transportButtonSize = if (isUltraCompact) 60.dp else if (isVeryCompact) 64.dp else if (isCompact) 68.dp else 72.dp
        val transportIconSize = if (isUltraCompact) 32.dp else if (isVeryCompact) 34.dp else 36.dp
        val utilityButtonSize = if (isUltraCompact) 44.dp else 48.dp
        val circleButtonSize = if (isUltraCompact) 48.dp else 54.dp
        val showVolumeControls = !isUltraCompact
        val artworkSize = minOf(
            maxWidth - (horizontalPadding * 2f),
            maxHeight * if (isUltraCompact) 0.25f else if (isVeryCompact) 0.28f else if (isCompact) 0.32f else 0.38f,
            if (isUltraCompact) 190.dp else if (isVeryCompact) 220.dp else if (isCompact) 280.dp else 340.dp
        ).coerceAtLeast(if (isUltraCompact) 130.dp else 160.dp)

        if (artworkUrl != null) {
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data(artworkUrl)
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        scaleX = 1.24f
                        scaleY = 1.24f
                    }
                    .blur(72.dp)
            )
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.White.copy(alpha = 0.16f),
                            Color(0xAA3B4B4A),
                            Color(0xF0101A1A)
                        )
                    )
                )
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(
                    start = horizontalPadding,
                    end = horizontalPadding,
                    top = topContentPadding,
                    bottom = bottomContentPadding
                ),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            IconButton(onClick = onDismiss) {
                Box(
                    modifier = Modifier
                        .width(48.dp)
                        .height(5.dp)
                        .clip(RoundedCornerShape(999.dp))
                        .background(Color.White.copy(alpha = 0.62f))
                )
            }

            Spacer(modifier = Modifier.height(handleSpacer))

            SwipeableArtworkSurface(
                artworkUrl = artworkUrl,
                artworkSize = artworkSize,
                canSkipNext = canSkipNext,
                canSkipPrevious = canSkipPrevious,
                previousRestartsCurrentTrack = positionMs > 5_000L,
                onPrevious = viewModel::previous,
                onNext = { viewModel.next() }
            )

            Spacer(modifier = Modifier.height(artworkSpacer))

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Bottom
            ) {
                Column(
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        text = title,
                        style = if (isVeryCompact) MaterialTheme.typography.titleLarge else MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = subtitle,
                        style = if (isVeryCompact) MaterialTheme.typography.bodyLarge else MaterialTheme.typography.titleMedium,
                        color = Color.White.copy(alpha = 0.76f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.clickable(enabled = primaryArtistName != null) {
                            primaryArtistName?.let { onArtistClick(it, primaryArtistBrowseId) }
                        }
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = statusMessage ?: " ",
                        style = MaterialTheme.typography.labelMedium,
                        color = if (error != null && recoveryStatus == null) MaterialTheme.colorScheme.error else Color.White.copy(alpha = 0.62f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                Spacer(modifier = Modifier.width(12.dp))

                Row(horizontalArrangement = Arrangement.spacedBy(if (isVeryCompact) 6.dp else 10.dp)) {
                    FrostedCircleButton(onClick = {}, size = circleButtonSize) {
                        Icon(Icons.Filled.FavoriteBorder, contentDescription = "Favori", tint = Color.White)
                    }
                    FrostedCircleButton(onClick = {}, size = circleButtonSize) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "Plus", tint = Color.White)
                    }
                }
            }

            Spacer(modifier = Modifier.height(sliderSpacer))

            Slider(
                value = sliderPosition.coerceIn(0f, durationMs.toFloat().coerceAtLeast(0f)),
                onValueChange = {
                    isSeeking = true
                    sliderPosition = it
                },
                onValueChangeFinished = {
                    viewModel.seekTo(sliderPosition.toLong())
                    isSeeking = false
                },
                valueRange = 0f..durationMs.toFloat().coerceAtLeast(0f).let { if (it <= 0f) 1f else it },
                enabled = durationMs > 0L,
                colors = SliderDefaults.colors(
                    thumbColor = Color.White,
                    activeTrackColor = Color.White,
                    inactiveTrackColor = Color.White.copy(alpha = 0.24f)
                ),
                modifier = Modifier.fillMaxWidth()
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = (if (isSeeking) sliderPosition.toLong() else positionMs).toMusicTime(),
                    style = MaterialTheme.typography.labelMedium,
                    color = Color.White.copy(alpha = 0.62f)
                )
                Text(
                    text = "-${max(durationMs - (if (isSeeking) sliderPosition.toLong() else positionMs), 0L).toMusicTime()}",
                    style = MaterialTheme.typography.labelMedium,
                    color = Color.White.copy(alpha = 0.48f)
                )
            }

            val middleSpacerHeight = if (isUltraCompact) 2.dp else if (isVeryCompact) 4.dp else if (isCompact) 10.dp else 20.dp
            if (isCompact) {
                Spacer(modifier = Modifier.height(middleSpacerHeight))
            } else {
                Spacer(modifier = Modifier.weight(1f))
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically
            ) {
                PlayerTransportButton(
                    enabled = canSkipPrevious,
                    onClick = viewModel::previous,
                    size = transportButtonSize
                ) {
                    Icon(
                        Icons.Filled.SkipPrevious,
                        contentDescription = "Précédent",
                        tint = Color.White,
                        modifier = Modifier.size(transportIconSize)
                    )
                }

                FilledIconButton(
                    onClick = viewModel::togglePlayPause,
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = Color.White.copy(alpha = 0.16f),
                        contentColor = Color.White
                    ),
                    modifier = Modifier.size(playButtonSize)
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(
                            color = Color.White,
                            strokeWidth = 3.dp,
                            modifier = Modifier.size(if (isUltraCompact) 26.dp else if (isVeryCompact) 30.dp else 34.dp)
                        )
                    } else {
                        Icon(
                            imageVector = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            contentDescription = if (isPlaying) "Pause" else "Lecture",
                            modifier = Modifier.size(playIconSize)
                        )
                    }
                }

                PlayerTransportButton(
                    enabled = canSkipNext,
                    onClick = { viewModel.next() },
                    size = transportButtonSize
                ) {
                    Icon(
                        Icons.Filled.SkipNext,
                        contentDescription = "Suivant",
                        tint = Color.White,
                        modifier = Modifier.size(transportIconSize)
                    )
                }
            }

            Spacer(modifier = Modifier.height(controlsBottomSpacer))

            if (showVolumeControls) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Filled.VolumeDown,
                        contentDescription = "Volume bas",
                        tint = Color.White.copy(alpha = 0.62f)
                    )
                    Slider(
                        value = volume,
                        onValueChange = { viewModel.setVolume(it) },
                        valueRange = 0f..1f,
                        colors = SliderDefaults.colors(
                            thumbColor = Color.White,
                            activeTrackColor = Color.White.copy(alpha = 0.92f),
                            inactiveTrackColor = Color.White.copy(alpha = 0.24f)
                        ),
                        modifier = Modifier
                            .weight(1f)
                            .padding(horizontal = 12.dp)
                    )
                    Icon(
                        Icons.Filled.VolumeUp,
                        contentDescription = "Volume haut",
                        tint = Color.White.copy(alpha = 0.62f)
                    )
                }
            }

            Spacer(modifier = Modifier.height(bottomActionsSpacer))

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                FrostedCircleButton(onClick = { showLyrics = true }, size = circleButtonSize) {
                    Icon(Icons.Filled.FormatQuote, contentDescription = "Paroles", tint = Color.White)
                }

                Spacer(modifier = Modifier.weight(1f))

                Surface(
                    shape = RoundedCornerShape(999.dp),
                    color = Color.White.copy(alpha = 0.12f)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        UtilityToggleButton(
                            active = repeatMode != RepeatMode.OFF,
                            onClick = viewModel::cycleRepeatMode,
                            size = utilityButtonSize
                        ) {
                            Icon(
                                imageVector = if (repeatMode == RepeatMode.ONE) Icons.Filled.RepeatOne else Icons.Filled.Repeat,
                                contentDescription = "Répétition",
                                tint = if (repeatMode != RepeatMode.OFF) Color.White else Color.White.copy(alpha = 0.72f)
                            )
                        }

                        UtilityDivider()

                        UtilityToggleButton(
                            active = shuffleEnabled,
                            onClick = viewModel::toggleShuffle,
                            size = utilityButtonSize
                        ) {
                            Icon(
                                Icons.Filled.Shuffle,
                                contentDescription = "Aléatoire",
                                tint = if (shuffleEnabled) Color.White else Color.White.copy(alpha = 0.72f)
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.weight(1f))

                FrostedCircleButton(onClick = { showQueue = true }, size = circleButtonSize) {
                    Icon(Icons.Filled.FormatListBulleted, contentDescription = "File d'attente", tint = Color.White)
                }
            }
            Spacer(modifier = Modifier.height(if (isUltraCompact) 4.dp else 8.dp))
        }
        
        if (showQueue) {
            ModalBottomSheet(
                onDismissRequest = { showQueue = false },
                sheetState = sheetState,
                containerColor = MaterialTheme.colorScheme.background,
                windowInsets = androidx.compose.foundation.layout.WindowInsets(0, 0, 0, 0)
            ) {
                QueueScreen(
                    viewModel = viewModel,
                    onDismiss = { showQueue = false }
                )
            }
        }
        
        if (showLyrics) {
            ModalBottomSheet(
                onDismissRequest = { showLyrics = false },
                sheetState = lyricsSheetState,
                containerColor = MaterialTheme.colorScheme.background,
                windowInsets = androidx.compose.foundation.layout.WindowInsets(0, 0, 0, 0)
            ) {
                LyricsScreen(
                    title = title,
                    artistLine = subtitle,
                    artworkUrl = artworkUrl,
                    durationSeconds = if (durationMs > 0) durationMs / 1000.0 else null,
                    onDismiss = { showLyrics = false }
                )
            }
        }
    }
}

@Composable
private fun SwipeableArtworkSurface(
    artworkUrl: String?,
    artworkSize: Dp,
    canSkipNext: Boolean,
    canSkipPrevious: Boolean,
    previousRestartsCurrentTrack: Boolean,
    onPrevious: () -> Unit,
    onNext: () -> Unit
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    val animationScope = rememberCoroutineScope()
    var offsetX by remember { mutableFloatStateOf(0f) }
    var isAnimatingSwipe by remember { mutableStateOf(false) }
    val widthPx = with(density) { artworkSize.toPx() }
    val resetSpring = spring<Float>(
        stiffness = Spring.StiffnessMediumLow,
        dampingRatio = Spring.DampingRatioNoBouncy
    )
    fun animateBackToCenter() {
        animationScope.launch {
            isAnimatingSwipe = true
            animate(
                initialValue = offsetX,
                targetValue = 0f,
                animationSpec = resetSpring
            ) { value, _ ->
                offsetX = value
            }
            isAnimatingSwipe = false
        }
    }
    fun animateTrackChange(direction: Float, action: () -> Unit) {
        animationScope.launch {
            isAnimatingSwipe = true
            animate(
                initialValue = offsetX,
                targetValue = direction * widthPx * 1.05f,
                animationSpec = tween(durationMillis = 140)
            ) { value, _ ->
                offsetX = value
            }
            action()
            offsetX = -direction * widthPx * 0.72f
            animate(
                initialValue = offsetX,
                targetValue = 0f,
                animationSpec = resetSpring
            ) { value, _ ->
                offsetX = value
            }
            isAnimatingSwipe = false
        }
    }

    Surface(
        shape = RoundedCornerShape(16.dp),
        color = Color.White.copy(alpha = 0.08f),
        tonalElevation = 0.dp,
        shadowElevation = 16.dp,
        modifier = Modifier
            .graphicsLayer {
                val progress = (abs(offsetX) / max(widthPx, 1f)).coerceIn(0f, 1f)
                translationX = offsetX
                alpha = 1f - (progress * 0.22f)
                scaleX = 1f - (progress * 0.035f)
                scaleY = 1f - (progress * 0.035f)
            }
            .pointerInput(widthPx, canSkipNext, canSkipPrevious, previousRestartsCurrentTrack) {
                awaitEachGesture {
                    if (isAnimatingSwipe) return@awaitEachGesture

                    val down = awaitFirstDown(requireUnconsumed = false)
                    val velocityTracker = VelocityTracker()
                    velocityTracker.addPosition(down.uptimeMillis, down.position)

                    var totalX = 0f
                    var totalY = 0f
                    var horizontalLocked = false
                    var verticalLocked = false
                    var released = false
                    val lockSlop = 8.dp.toPx()

                    while (!released) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break

                        if (change.changedToUpIgnoreConsumed()) {
                            released = true
                            continue
                        }

                        val delta = change.positionChange()
                        totalX += delta.x
                        totalY += delta.y
                        velocityTracker.addPosition(change.uptimeMillis, change.position)

                        if (!horizontalLocked && !verticalLocked) {
                            val absX = abs(totalX)
                            val absY = abs(totalY)
                            if (absX > lockSlop || absY > lockSlop) {
                                when {
                                    absX > absY * 1.25f -> horizontalLocked = true
                                    absY > absX * 1.1f -> verticalLocked = true
                                }
                            }
                        }

                        if (verticalLocked) {
                            break
                        }

                        if (horizontalLocked) {
                            change.consume()
                            val hasTarget = if (totalX > 0f) canSkipPrevious else canSkipNext
                            val resistance = if (!hasTarget || (totalX > 0f && previousRestartsCurrentTrack)) 0.42f else 1f
                            val targetOffset = (totalX * resistance).coerceIn(-widthPx * 0.95f, widthPx * 0.95f)
                            offsetX = targetOffset
                        }
                    }

                    if (!horizontalLocked || verticalLocked) {
                        animateBackToCenter()
                        return@awaitEachGesture
                    }

                    val velocityX = velocityTracker.calculateVelocity().x
                    val widthThreshold = widthPx * 0.22f
                    val velocityThreshold = widthPx * 2.4f
                    val direction = when {
                        offsetX > widthThreshold || velocityX > velocityThreshold -> 1f
                        offsetX < -widthThreshold || velocityX < -velocityThreshold -> -1f
                        else -> 0f
                    }

                    when {
                        direction == 0f -> {
                            animateBackToCenter()
                        }
                        direction > 0f && previousRestartsCurrentTrack -> {
                            onPrevious()
                            animateBackToCenter()
                        }
                        direction > 0f && canSkipPrevious -> {
                            animateTrackChange(direction, onPrevious)
                        }
                        direction < 0f && canSkipNext -> {
                            animateTrackChange(direction, onNext)
                        }
                        else -> {
                            animateBackToCenter()
                        }
                    }
                }
            }
    ) {
        if (artworkUrl != null) {
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data(artworkUrl)
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(artworkSize)
            )
        } else {
            Box(
                modifier = Modifier
                    .size(artworkSize)
                    .background(Color.White.copy(alpha = 0.10f))
            )
        }
    }
}

@Composable
private fun FrostedCircleButton(
    onClick: () -> Unit,
    size: androidx.compose.ui.unit.Dp = 44.dp,
    content: @Composable () -> Unit
) {
    val interactionSource = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.12f))
            .clickable(
                interactionSource = interactionSource,
                indication = LocalIndication.current,
                onClick = onClick
            ),
        contentAlignment = Alignment.Center
    ) {
        content()
    }
}

@Composable
private fun PlayerTransportButton(
    enabled: Boolean,
    onClick: () -> Unit,
    size: androidx.compose.ui.unit.Dp = 72.dp,
    content: @Composable () -> Unit
) {
    IconButton(
        onClick = onClick,
        enabled = enabled,
        colors = IconButtonDefaults.iconButtonColors(
            containerColor = Color.Transparent,
            contentColor = Color.White,
            disabledContentColor = Color.White.copy(alpha = 0.32f)
        ),
        modifier = Modifier.size(size)
    ) {
        content()
    }
}

@Composable
private fun UtilityToggleButton(
    active: Boolean,
    onClick: () -> Unit,
    size: androidx.compose.ui.unit.Dp = 48.dp,
    content: @Composable () -> Unit
) {
    IconButton(
        onClick = onClick,
        colors = IconButtonDefaults.iconButtonColors(
            containerColor = Color.Transparent,
            contentColor = if (active) Color.White else Color.White.copy(alpha = 0.72f)
        ),
        modifier = Modifier.size(size)
    ) {
        content()
    }
}

@Composable
private fun UtilityDivider() {
    Box(
        modifier = Modifier
            .width(1.dp)
            .height(22.dp)
            .background(Color.White.copy(alpha = 0.18f))
    )
}

private fun resolvedArtworkUrl(
    albumArtwork: String?,
    songArtwork: String?,
    payloadArtwork: String?
): String? {
    return albumArtwork ?: songArtwork ?: payloadArtwork
}

private fun String.highResolutionArtworkUrl(): String {
    return when {
        contains("googleusercontent.com") -> upgradeGoogleArtworkUrl()
        contains("ytimg.com") -> upgradeYouTubeArtworkUrl()
        else -> this
    }
}

private fun String.upgradeGoogleArtworkUrl(): String {
    val sizeSuffix = Regex("=w\\d+-h\\d+[^/?#]*$")
    return if (sizeSuffix.containsMatchIn(this)) {
        replace(sizeSuffix, "=w1200-h1200-l90-rj")
    } else {
        "$this=w1200-h1200-l90-rj"
    }
}

private fun String.upgradeYouTubeArtworkUrl(): String {
    val videoId = Regex("/vi/([^/]+)/").find(this)?.groupValues?.getOrNull(1) ?: return this
    return "https://i.ytimg.com/vi/$videoId/maxresdefault.jpg"
}

private fun Long.toMusicTime(): String {
    val totalSeconds = (this / 1000L).coerceAtLeast(0L)
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%d:%02d".format(minutes, seconds)
}
