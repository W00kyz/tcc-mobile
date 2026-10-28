/// Every user-facing pt-BR string in the app, in one place (RNF02).
///
/// Widgets never hold literal copy — they reference `AppStrings.*`. This is a
/// plain constant table, not a full i18n framework: the app ships pt-BR only
/// (Android, PU/UFCG field workers), so a `Locale`-aware `.arb` toolchain would
/// be machinery with no second locale to justify it. Interpolation and
/// pluralization are `static String name(...)` helpers.
///
/// Example:
/// ```dart
/// FilledButton(onPressed: scan, child: const Text(AppStrings.scanQrButton));
/// Text(AppStrings.routePendingSync(count));
/// ```
abstract final class AppStrings {
  // --- common (shared across screens) ---
  static const String commonCancel = 'Cancelar';
  static const String commonConfirm = 'Confirmar';
  static const String commonSave = 'Salvar';
  static const String commonBack = 'Voltar';

  /// A distance rendered as `<n> m` (candidate tiles, route legs).
  static String meters(int m) => '$m m';

  // --- login ---
  static const String loginBrand = 'PU · UFCG';
  static const String loginTitle = 'Monitoramento de Rotas';
  static const String loginEmailLabel = 'E-mail';
  static const String loginPasswordLabel = 'Senha';
  static const String loginSubmitButton = 'Entrar';
  static const String loginSubmitting = 'Entrando…';
  static const String loginInvalidCredentials = 'E-mail ou senha incorretos.';
  static const String loginNetworkError =
      'Sem conexão com o servidor. Tente novamente quando houver sinal.';
  static const String loginForgotPassword = 'Esqueci minha senha';
  static const String forgotPasswordTitle = 'Recuperar senha';
  static const String forgotPasswordIntro =
      'Informe seu e-mail cadastrado. Enviaremos um link para definir uma '
      'nova senha.';
  static const String forgotPasswordSend = 'Enviar link';
  static const String forgotPasswordCancel = 'Cancelar';
  static const String forgotPasswordSent =
      'Se o e-mail estiver cadastrado, você receberá um link em instantes.';
  static const String forgotPasswordError =
      'Não foi possível enviar o link. Verifique a conexão e tente novamente.';
  static const String loginCreateAccount = 'Criar conta';

  // --- self-registration (alocação automática §9) ---
  static const String registrationTitle = 'Criar conta';
  static const String registrationNameLabel = 'Nome';
  static const String registrationEmailLabel = 'E-mail';
  static const String registrationPasswordLabel = 'Senha';
  static const String registrationCompanyLabel = 'Empresa';
  static const String registrationNameRequired = 'Informe seu nome.';
  static const String registrationEmailInvalid = 'Informe um e-mail válido.';
  static const String registrationPasswordTooShort =
      'A senha precisa ter pelo menos 8 caracteres.';
  static const String registrationPasswordTooLong =
      'A senha pode ter no máximo 128 caracteres.';
  static const String registrationCompanyRequired = 'Escolha sua empresa.';
  static const String registrationAcceptNotice = 'Li e aceito';
  static const String registrationSubmit = 'Enviar cadastro';
  static const String registrationSubmitting = 'Enviando…';
  static const String registrationSent =
      'Cadastro enviado. Aguarde a aprovação do gestor.';
  static const String registrationEmailTaken =
      'Este e-mail já está cadastrado.';
  static const String registrationNoticeOutdated =
      'O aviso de privacidade foi atualizado. Leia e aceite a nova versão.';
  static const String registrationError =
      'Não foi possível enviar o cadastro. Verifique a conexão e tente '
      'novamente.';
  static const String registrationInvalidData =
      'Verifique os dados informados.';
  static const String registrationCompanyGone =
      'A empresa escolhida não está mais disponível. Escolha novamente.';
  static const String registrationServerError =
      'O servidor não conseguiu registrar o cadastro. Tente novamente mais '
      'tarde.';
  static const String registrationLoadError =
      'Não foi possível carregar as empresas e o aviso de privacidade.';
  static const String registrationRetry = 'Tentar novamente';

  /// The `Versão <n>` label under the privacy notice title.
  static String registrationNoticeVersion(int version) => 'Versão $version';

  // --- approval gate (alocação automática §9) ---
  static const String approvalPendingMessage =
      'Seu cadastro está aguardando aprovação do gestor.';
  static const String approvalRejectedMessage =
      'Seu cadastro não foi aprovado.';
  static const String approvalDeactivatedMessage =
      'Seu cadastro foi desativado pelo gestor.';
  static const String approvalRefreshButton = 'Atualizar';
  static const String approvalExitButton = 'Sair';
  static const String approvalStillPending =
      'Seu cadastro ainda aguarda aprovação.';
  static const String approvalNetworkError =
      'Sem conexão com o servidor. Tente novamente quando houver sinal.';

  /// The manager's reason under a rejection.
  static String approvalRejectionReason(String reason) => 'Motivo: $reason';

  // --- route screen ---
  static const String routeLoadError = 'Não foi possível carregar sua rota.';
  static const String routeStartButton = 'Iniciar rota';
  static const String routeConcludeButton = 'Concluir';
  static const String routeSignalImpossibilityButton =
      'Sinalizar impossibilidade';
  static const String routeNotificationsTooltip = 'Notificações';
  static const String routeCheckInDone = 'Check-in registrado.';
  static const String routeCheckOutDone = 'Check-out registrado.';
  static const String routeImpedimentReported = 'Impossibilidade sinalizada.';
  static const String routeLocationUnavailable =
      'Não foi possível obter sua localização.';
  static const String routeLocationUnavailableCheckIn =
      'Sem localização agora. O registro foi feito mesmo assim.';

  // --- route screen · batches (spec 2026-10-20-alocacao-automatica §6.4) ---
  static const String routeNotServiceDay = 'Hoje não é dia de serviço.';
  static const String routeStartOffline =
      'Conecte-se à internet para iniciar a rota.';
  static const String routeOutsideCampus =
      'Você precisa estar no campus para iniciar.';
  static const String routeWorkdayOver = 'O expediente de hoje já terminou.';
  static const String routeNoMorePoints = 'Não há mais pontos agora.';
  static const String routeCheckAgainButton = 'Verificar de novo';
  static const String routeStartFailed =
      'Não foi possível iniciar a rota. Tente novamente.';
  static const String routePausedTitle = 'Rota pausada';
  static const String routeNextBatchOffline =
      'Conecte-se para receber mais pontos';

  /// A released stop of the current batch: `Liberado · <motivo>`, or just
  /// `Liberado` when the server sent no reason.
  static String routeStopReleased(String? reason) =>
      reason == null ? 'Liberado' : 'Liberado · $reason';

  /// Why a paused route's points went back to the pool.
  static String routePausedReason(String reason) => 'Motivo: $reason';

  /// A stop's `release_reason` code in words (same labels as the dashboard).
  static String releaseReasonLabel(String code) => switch (code) {
    'IMPEDIMENT' => 'Impedimento',
    'ROUTE_REMAINDER' => 'Resto da rota impedido',
    'LEFT_CAMPUS' => 'Saiu do campus',
    'LOCATION_SILENCE' => 'Sem localização',
    'END_OF_DAY' => 'Fim do expediente',
    _ => code,
  };

  // --- route screen · sync banner ---
  static const String routeSyncBlockedBanner =
      'Sincronização bloqueada — toque para ver';
  static const String routeAllSynced = 'Tudo sincronizado';
  static const String routeChipPending = 'Pendente';
  static const String routeChipBlocked = 'Bloqueado';

  /// `<n> ação(ões) aguardando sincronização`.
  static String routePendingSync(int n) =>
      '$n ${n == 1 ? 'ação' : 'ações'} aguardando sincronização';

  /// The travel-from-previous leg line, e.g. `a 120 m · 2 min`.
  static String routeLeg(String leg) => 'a $leg';

  // --- route screen · evidence ---
  static const String routeAddPhotoButton = 'Adicionar foto';
  static const String routeAddNoteButton = 'Adicionar observação';
  static const String routeNoteHint = 'Descreva a observação';
  static const String routeEvidencePhotoLabel = 'Foto';
  static const String routeEvidenceLoadError =
      'Não foi possível carregar as evidências.';
  static const String routePhotoAdded = 'Foto adicionada.';
  static const String routePhotoAddError = 'Não foi possível adicionar a foto.';
  static const String routeNoteAdded = 'Observação adicionada.';
  static const String routeNoteAddError =
      'Não foi possível adicionar a observação.';

  // --- route screen · evidence requirement ---
  /// `Tire pelo menos 2 fotos (faltam N)`.
  static String evidenceMissingHint(int missing) =>
      'Tire pelo menos 2 fotos (faltam $missing)';

  // --- complaints and suggestions dialog ---
  static const String complaintsDialogTitle =
      'Reclamações e Sugestões (opcional)';
  static const String complaintsContinue = 'Continuar';

  // --- map ---
  static const String mapApproximateLegLabel = 'trajeto aproximado';

  // --- scan screen ---
  static const String scanInvalidQr =
      'Esse QR não é do sistema. Tente o QR fixado no andar.';
  static const String scanFramingPrompt = 'Aponte para o QR Code do andar';
  static const String scanTorch = 'Lanterna';
  static const String scanCancel = 'Cancelar';
  static const String scanPermissionTitle = 'A câmera está desligada';
  static const String scanPermissionBody =
      'O app precisa da câmera para ler o QR Code fixado no andar e '
      'confirmar que você está no lugar certo.';
  static const String scanOpenSettings = 'Abrir configurações';
  static const String scanCameraError = 'Não foi possível abrir a câmera.';

  /// Context line under the frame at check-in: `Entrada · <prédio>`.
  static String scanEntryContext(String building) => 'Entrada · $building';

  /// Context line under the frame at check-out:
  /// `Saída · <prédio> · <andar>`.
  static String scanExitContext(String building, String floor) =>
      'Saída · $building · $floor';

  // --- blocked sync screen ---
  static const String blockedSyncAppBarTitle = 'Sincronização bloqueada';
  static const String blockedSyncLoadError =
      'Não foi possível carregar as operações bloqueadas.';
  static const String blockedSyncEmpty = 'Nenhuma operação bloqueada.';
  static const String blockedSyncRetryButton = 'Tentar de novo';
  static const String blockedSyncUnknownError = 'Erro desconhecido';
  static const String blockedSyncKindCheckIn = 'Check-in';
  static const String blockedSyncKindCheckOut = 'Check-out';
  static const String blockedSyncKindPhoto = 'Foto';
  static const String blockedSyncKindNote = 'Observação';
  static const String blockedSyncKindImpediment = 'Impedimento';

  /// A `<kind> — <reference>` outbox-row label.
  static String blockedSyncRowLabel(String kind, String reference) =>
      '$kind — $reference';

  // --- released stops with local data: blocked sync screen and /recursos
  // (alocação automática §7.5) ---
  static const String releasedStopAppealButton = 'Recorrer';
  static const String releasedStopDiscardButton = 'Descartar';
  static const String releasedStopDiscardTitle = 'Descartar dados deste ponto?';
  static const String releasedStopDiscardBody =
      'As fotos e registros feitos offline neste ponto serão '
      'apagados do aparelho.';
  static const String releasedStopDiscarded = 'Dados do ponto descartados.';

  /// The heading of a stop whose late writes the server refused.
  static String releasedStopTitle(String reference) =>
      'Ponto liberado — $reference';

  /// Why the server released that stop.
  static String releasedStopReason(String reason) => 'Motivo: $reason';

  /// Under a released stop the worker can no longer appeal.
  static const String releasedStopNotAppealable =
      'Não aceita recurso — você pode descartar os dados.';

  // --- room picker ---
  static const String roomPickerPrompt =
      'Vários pontos correspondem — escolha o certo:';

  // --- impediment dialog (alocação automática §7.1) ---
  static const String impedimentDialogTitle = 'Não consigo fazer este ponto';
  static const String impedimentNoteHint = 'Observação (opcional)';
  static const String impedimentRemainderSwitch = 'Não consigo continuar hoje';
  static const String impedimentReasonAccessBlocked = 'Acesso bloqueado';
  static const String impedimentReasonSiteRefusal = 'Recusa do local';
  static const String impedimentReasonHealthIssue = 'Problema de saúde';
  static const String impedimentReasonOther = 'Outro';

  // --- appeals (alocação automática §7.5) ---
  static const String appealsTooltip = 'Recursos';
  static const String appealsAppBarTitle = 'Recursos';
  static const String appealsLocalTitle =
      'Pontos liberados com dados neste aparelho';
  static const String appealsEligibleTitle =
      'Pontos liberados que você pode contestar';
  static const String appealsEligibleEmpty = 'Nenhum ponto para contestar.';
  static const String appealsMineTitle = 'Meus recursos';
  static const String appealsMineEmpty = 'Você ainda não enviou recursos.';
  static const String appealsLoadError =
      'Não foi possível carregar os recursos.';
  static const String releasedStopsSnackbar =
      'Estes pontos foram liberados — você pode recorrer.';
  static const String releasedStopsSnackbarAction = 'Recorrer';

  /// The details line of a contestable point.
  static String appealEligibleDetails({
    required String building,
    required String floor,
    required String reason,
    required String deadline,
  }) => '$building · $floor\nMotivo: $reason · Prazo: $deadline';

  /// The details line of a filed appeal: `<prédio> · enviado em <quando>`.
  static String appealFiledDetails(String building, String filedAt) =>
      '$building · enviado em $filedAt';

  /// An appeal's `status` in words.
  static String appealStatusLabel(String status) => switch (status) {
    'PENDING' => 'Em análise',
    'ACCEPTED' => 'Aceito',
    'REJECTED' => 'Recusado',
    _ => status,
  };

  /// Who decided an appeal and, when they wrote one, their note.
  static String appealReview(String reviewer, String? note) =>
      note == null ? 'Por $reviewer' : '$reviewer: $note';

  // --- appeal form (alocação automática §7.5) ---
  static const String appealFormTitle = 'Recorrer';
  static const String appealReasonLabel = 'Motivo';
  static const String appealReasonNoSignal = 'Fiquei sem sinal';
  static const String appealReasonLeftBriefly = 'Saí rapidamente do campus';
  static const String appealReasonAppClosed = 'O app fechou ou descarregou';
  static const String appealReasonOther = 'Outro';
  static const String appealNoteHint = 'Observação (opcional)';
  static const String appealClaimedTimeLabel = 'Horário declarado';
  static const String appealClaimedTimeNone = 'Não informado';
  static const String appealSubmit = 'Enviar recurso';
  static const String appealLocalDataWarning =
      'As fotos feitas offline neste ponto não serão enviadas com '
      'o recurso e serão apagadas do aparelho.';
  static const String appealWarningConfirm = 'Enviar';
  static const String appealSent = 'Recurso enviado.';
  static const String appealSentCleanupFailed =
      'O recurso foi enviado, mas os dados deste ponto não puderam ser '
      'apagados do aparelho. Toque em "Enviar recurso" de novo.';
  static const String appealSendError =
      'Não foi possível enviar o recurso. Verifique a conexão e tente '
      'novamente.';

  /// `Motivo da liberação: <motivo>`.
  static String appealReleaseReason(String reason) =>
      'Motivo da liberação: $reason';

  /// Why the server refused an appeal (409 `NOT_APPEALABLE` `reason_code`).
  static String appealRefusal(String reasonCode) => switch (reasonCode) {
    'NOT_OWNER' => 'Este ponto não é seu.',
    'NOT_RELEASED' => 'Este ponto não está liberado.',
    'REASON_NOT_APPEALABLE' =>
      'Pontos liberados por impedimento não aceitam recurso.',
    'ALREADY_CHECKED_OUT' => 'A conclusão deste ponto já foi registrada.',
    'WINDOW_EXPIRED' => 'O prazo para recorrer deste ponto terminou.',
    'ALREADY_APPEALED' => 'Você já recorreu deste ponto.',
    _ => appealSendError,
  };

  // --- evidence note dialog ---
  static const String formAddNoteDialogTitle = 'Adicionar observação';

  // --- notifications screen ---
  static const String notificationsAppBarTitle = 'Notificações';
  static const String notificationsLoadError =
      'Não foi possível carregar as notificações.';
  static const String notificationsEmpty = 'Nenhuma notificação.';
  static const String notificationKindAlert = 'Alerta';
  static const String notificationKindImpedimentReported = 'Impossibilidade';
  static const String notificationKindAppealFiled = 'Recurso';

  /// `<kind> · <timestamp>` metadata line under a notification.
  static String notificationMeta(String kind, String timestamp) =>
      '$kind · $timestamp';

  // --- consent gate (Etapa 11 Task 10) ---
  static const String consentTitle = 'Antes de continuar';
  static const String consentBody =
      '[Texto de consentimento — placeholder. A Prefeitura Universitária da '
      'UFCG coleta seus dados de identificação, localização durante a jornada '
      'de trabalho e registros de execução de rota para fins de fiscalização '
      'da prestação de serviços (LGPD, art. 7º). O tratamento segue a '
      'finalidade descrita e os dados são retidos pelo prazo definido na '
      'política interna. Substituir por texto revisado pelo DPO antes do '
      'piloto.]';
  static const String consentAcceptButton = 'Li e concordo';
  static const String consentLoadError =
      'Não foi possível carregar o termo de consentimento.';
  static const String consentExitButton = 'Sair';

  // --- "meus dados" screen (Etapa 11 Task 11) ---
  static const String myDataTitle = 'Meus dados';
  static const String myDataLoading = 'Carregando seus dados…';
  static const String myDataError = 'Não foi possível carregar seus dados.';
  static const String myDataEmpty = 'Nenhum dado registrado.';
  static const String myDataSectionProfile = 'Perfil';
  static const String myDataSectionConsent = 'Consentimento';
  static const String myDataSectionActivity = 'Atividade';
  static const String myDataSectionFieldWorker = 'Cadastro de campo';
  static const String myDataSectionAuthEvents = 'Acessos à conta';
  static const String myDataSectionExecutions = 'Execuções de rota';
  static const String myDataSectionEvidence = 'Evidências';
  static const String myDataSectionPositions = 'Registros de localização';
  static const String myDataSectionNotifications = 'Notificações';
  static const String myDataFieldEmail = 'E-mail';
  static const String myDataFieldName = 'Nome';
  static const String myDataFieldRole = 'Perfil de acesso';
  static const String myDataFieldActive = 'Conta ativa';
  static const String myDataFieldInactive = 'Conta inativa';
  static const String myDataFieldCreatedAt = 'Criada em';
  static const String myDataFieldFullName = 'Nome completo';
  static const String myDataFieldCompany = 'Empresa contratada';
  static const String myDataFieldServiceTypes = 'Tipos de serviço';
  static const String myDataFieldTotal = 'Total';
  static const String myDataFieldFirstAt = 'Primeiro registro';
  static const String myDataFieldLastAt = 'Último registro';
  static const String myDataFieldEvidenceItems = 'Itens';
  static const String myDataFieldEvidenceBytes = 'Tamanho aproximado';
  static const String myDataFieldNotificationsUnread = 'Não lidas';

  /// A `versão <n>` label for a consent-history entry.
  static String myDataConsentVersion(int version) => 'versão $version';

  /// An approximate size rendered in kilobytes, e.g. `~ 1234 KB`.
  static String myDataKilobytes(int bytes) => '~ ${(bytes / 1024).round()} KB';

  // --- data-collection notice (Etapa 11 Task 12) ---
  static const String collectionNotificationTitle =
      'Coleta de localização ativa';
  static const String collectionNotificationBody =
      'Sua localização está sendo registrada durante a rota para fins de '
      'fiscalização.';
  static const String collectionNotificationChannelName =
      'Coleta de localização';
  static const String collectionNotificationChannelDescription =
      'Aviso persistente enquanto a localização é registrada durante a rota.';
  static const String locationPurposeRationale =
      'A localização é usada apenas para confirmar a presença nos pontos da '
      'rota e não é compartilhada fora da Prefeitura Universitária.';

  // --- location in two modes and the silence warning (alocação §7.3) ---
  /// The fixed notification of the background-location foreground service.
  static const String routeInProgressTitle = 'Rota em andamento';
  static const String routeInProgressText = collectionNotificationBody;
  static const String locationAlwaysRationale =
      'Para não perder seus pontos com a tela bloqueada, permita a '
      'localização o tempo todo durante a rota.';
  static const String locationForegroundOnlyNote =
      'Sem essa permissão, abra o app de tempos em tempos durante a rota.';
  static const String locationPromptContinue = 'Continuar';
  static const String locationPromptUnderstood = 'Entendi';
  static const String silenceNotificationTitle = 'Localização não enviada';
  static const String silenceNotificationChannelName = 'Aviso de localização';
  static const String silenceNotificationChannelDescription =
      'Avisa quando a localização não é enviada há algum tempo durante a '
      'rota.';

  /// The silence warning: [silent] minutes without a sent position, the
  /// points released in [untilRelease] minutes — or, with none left, the
  /// [silenceWarningPastRelease] copy.
  static String silenceWarning(int silent, int untilRelease) =>
      untilRelease <= 0
      ? silenceWarningPastRelease(silent)
      : 'Sem enviar sua localização há $silent min. Seus pontos serão '
            'liberados em $untilRelease min. Abra o app ou procure sinal.';

  /// The warning once the release window has run out.
  static String silenceWarningPastRelease(int silent) =>
      'Sem enviar sua localização há $silent min. Seus pontos podem ter '
      'sido liberados. Abra o app ou procure sinal.';

  // --- batch card atoms (not-by-colour labels) ---
  static String slotDone(String hour) => 'Concluído às $hour';

  /// A stop done with no known hour (an old server answer without
  /// `done_at`).
  static const String slotDoneNoHour = 'Concluído';
  static String slotReleased(String? reason) =>
      reason == null ? 'Liberado' : 'Liberado: $reason';
  static const String slotPending = 'Pendente';
  static const String slotNext = 'Próximo';
  static const String slotInProgress = 'Em andamento';
  static const String slotPendingSync = 'aguardando envio';
  static String batchCardTitle(int n) => 'CARTÃO DO LOTE $n';
  static String batchCardSubtitle(int total) => 'Junte os $total carimbos';
  static String batchReleasedCount(int n) =>
      n == 1 ? '1 liberado' : '$n liberados';

  // --- map home (redesign §6.2, §6.10) ---
  static const String scanQrButton = 'Escanear QR';
  static const String nextStopLabel = 'Próxima parada';
  static const String inProgressStopLabel = 'Em andamento';
  static const String myPositionTooltip = 'Minha posição';
  static const String accountMenuTooltip = 'Menu da conta';
  static const String collectionChip = 'Coleta de localização ativa';
  static const String dayNoService = 'Hoje não tem serviço para você';
  static const String dayResumeButton = 'Retomar';
  static const String dayDoneTitle = 'Dia concluído';
  static const String retryButton = 'Tentar de novo';

  /// `Lote <n> · <done> de <total> pontos hoje` (top bar).
  static String dayProgress(int batch, int done, int total) =>
      'Lote $batch · $done de $total pontos hoje';

  /// The day's summary under "Dia concluído".
  static String dayDoneSummary(int done) =>
      done == 1 ? '1 ponto concluído hoje' : '$done pontos concluídos hoje';

  /// The silence chip over the map: `Sem localização há <min> min`.
  static String silenceChip(int minutes) => 'Sem localização há $minutes min';

  /// A building's floor line in the sheet: `<prédio> · <andar>`.
  static String buildingFloor(String building, String floor) =>
      '$building · $floor';
}
