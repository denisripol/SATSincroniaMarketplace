object FrmVincularProduto: TFrmVincularProduto
  Left = 0
  Top = 0
  Caption = 'Vincular Produto'
  ClientHeight = 480
  ClientWidth = 620
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
    Width = 620
    Height = 60
    Align = alTop
    Color = clWhite
    ParentBackground = False
    TabOrder = 0
    ExplicitWidth = 618
    object lblTitulo: TLabel
      Left = 16
      Top = 10
      Width = 177
      Height = 21
      Caption = 'Vincular Produto F'#237'sico'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblFiltro: TLabel
      Left = 260
      Top = 20
      Width = 38
      Height = 15
      Caption = 'Buscar:'
    end
    object edtFiltro: TEdit
      Left = 316
      Top = 16
      Width = 200
      Height = 23
      TabOrder = 0
      OnKeyPress = edtFiltroKeyPress
    end
    object CmdBuscar: TBitBtn
      Left = 524
      Top = 14
      Width = 80
      Height = 28
      Caption = 'Buscar'
      TabOrder = 1
      OnClick = CmdBuscarClick
    end
  end
  object Grid: TStringGrid
    Left = 0
    Top = 60
    Width = 620
    Height = 364
    Align = alClient
    ColCount = 3
    DefaultColWidth = 150
    FixedCols = 0
    RowCount = 1
    FixedRows = 0
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goRowSelect]
    TabOrder = 1
    OnDblClick = GridDblClick
    ExplicitWidth = 618
    ExplicitHeight = 356
    ColWidths = (
      90
      380
      100)
  end
  object pnlRodape: TPanel
    Left = 0
    Top = 424
    Width = 620
    Height = 56
    Align = alBottom
    TabOrder = 2
    ExplicitTop = 416
    ExplicitWidth = 618
    object CmdSelecionar: TBitBtn
      Left = 344
      Top = 12
      Width = 120
      Height = 32
      Caption = 'Selecionar'
      TabOrder = 0
      OnClick = CmdSelecionarClick
    end
    object CmdCancelar: TBitBtn
      Left = 480
      Top = 12
      Width = 120
      Height = 32
      Caption = 'Cancelar'
      TabOrder = 1
      OnClick = CmdCancelarClick
    end
  end
end
