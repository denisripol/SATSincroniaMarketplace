object FrmPedidosMarketplace: TFrmPedidosMarketplace
  Left = 0
  Top = 0
  Caption = 'Pedidos - Marketplace'
  ClientHeight = 520
  ClientWidth = 820
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object pnlTopo: TPanel
    Left = 0
    Top = 0
    Width = 820
    Height = 60
    Align = alTop
    Color = clWhite
    ParentBackground = False
    TabOrder = 0
    object lblTitulo: TLabel
      Left = 16
      Top = 12
      Width = 61
      Height = 21
      Caption = 'Pedidos'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblFiltro: TLabel
      Left = 500
      Top = 20
      Width = 76
      Height = 15
      Caption = #218'ltimos (dias):'
    end
    object edtDiasAtras: TEdit
      Left = 596
      Top = 16
      Width = 50
      Height = 23
      TabOrder = 0
      Text = '15'
    end
    object CmdAtualizar: TBitBtn
      Left = 656
      Top = 14
      Width = 100
      Height = 28
      Caption = 'Atualizar'
      TabOrder = 1
      OnClick = CmdAtualizarClick
    end
  end
  object Grid: TStringGrid
    Left = 0
    Top = 60
    Width = 820
    Height = 260
    Align = alTop
    ColCount = 4
    DefaultColWidth = 190
    FixedCols = 0
    RowCount = 1
    FixedRows = 0
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goRowSelect]
    TabOrder = 1
    OnClick = GridClick
    OnSelectCell = GridSelectCell
    ColWidths = (
      190
      150
      190
      120)
  end
  object pnlAcoes: TPanel
    Left = 0
    Top = 320
    Width = 820
    Height = 96
    Align = alTop
    TabOrder = 2
    object CmdDespachar: TBitBtn
      Left = 16
      Top = 12
      Width = 140
      Height = 32
      Caption = 'Despachar'
      Enabled = False
      TabOrder = 0
      OnClick = CmdDespacharClick
    end
    object CmdCancelar: TBitBtn
      Left = 164
      Top = 12
      Width = 140
      Height = 32
      Caption = 'Cancelar'
      Enabled = False
      TabOrder = 1
      OnClick = CmdCancelarClick
    end
    object CmdAprovarCancelamento: TBitBtn
      Left = 312
      Top = 12
      Width = 200
      Height = 32
      Caption = 'Aprovar Cancelamento'
      Enabled = False
      TabOrder = 2
      OnClick = CmdAprovarCancelamentoClick
    end
    object CmdReprovarCancelamento: TBitBtn
      Left = 520
      Top = 12
      Width = 200
      Height = 32
      Caption = 'Reprovar Cancelamento'
      Enabled = False
      TabOrder = 3
      OnClick = CmdReprovarCancelamentoClick
    end
    object CmdGerarEtiqueta: TBitBtn
      Left = 16
      Top = 52
      Width = 140
      Height = 32
      Caption = 'Gerar Etiqueta'
      Enabled = False
      TabOrder = 4
      OnClick = CmdGerarEtiquetaClick
    end
    object CmdBaixarEtiqueta: TBitBtn
      Left = 164
      Top = 52
      Width = 140
      Height = 32
      Caption = 'Baixar Etiqueta'
      Enabled = False
      TabOrder = 5
      OnClick = CmdBaixarEtiquetaClick
    end
    object CmdBaixarNF: TBitBtn
      Left = 312
      Top = 52
      Width = 160
      Height = 32
      Caption = 'Baixar Nota Fiscal'
      Enabled = False
      TabOrder = 6
      OnClick = CmdBaixarNFClick
    end
    object CmdEnviarNF: TBitBtn
      Left = 480
      Top = 52
      Width = 160
      Height = 32
      Caption = 'Enviar Nota Fiscal'
      Enabled = False
      TabOrder = 7
      OnClick = CmdEnviarNFClick
    end
    object CmdBaixarPedidoSAT: TBitBtn
      Left = 648
      Top = 52
      Width = 160
      Height = 32
      Caption = 'Baixar Pedido SAT'
      Enabled = False
      TabOrder = 8
      OnClick = CmdBaixarPedidoSATClick
    end
  end
  object MemoLog: TMemo
    Left = 0
    Top = 416
    Width = 820
    Height = 104
    Align = alClient
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 3
  end
  object SaveDialog1: TSaveDialog
    DefaultExt = 'pdf'
    Filter = 'Arquivo PDF (*.pdf)|*.pdf'
    Title = 'Salvar arquivo'
    Left = 760
    Top = 16
  end
  object OpenDialog1: TOpenDialog
    DefaultExt = 'pdf'
    Filter = 'Arquivo PDF (*.pdf)|*.pdf'
    Title = 'Selecionar arquivo da Nota Fiscal'
    Left = 760
    Top = 56
  end
end
